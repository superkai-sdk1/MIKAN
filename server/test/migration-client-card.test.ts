import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import Database from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';
import { afterEach, describe, expect, it } from 'vitest';
import { MIGRATIONS_DIR } from '../src/db/client.js';
import * as schema from '../src/db/schema.js';
import { searchClients, updateClient } from '../src/domain/clients.js';
import { getClientRow } from '../src/domain/refs.js';
import { clientOut } from '../src/lib/serialize.js';

/** A copy of the migrations folder that stops before `0006_client_last_name_telegram_nick`. */
function migrationsBeforeClientCard(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mikan-migrations-'));
  fs.cpSync(MIGRATIONS_DIR, dir, { recursive: true });
  const journalPath = path.join(dir, 'meta', '_journal.json');
  const journal = JSON.parse(fs.readFileSync(journalPath, 'utf8')) as { entries: Array<{ tag: string }> };
  journal.entries = journal.entries.filter((e) => e.tag < '0006');
  fs.writeFileSync(journalPath, JSON.stringify(journal));
  return dir;
}

describe('migration 0006_client_last_name_telegram_nick', () => {
  const dirs: string[] = [];
  afterEach(() => {
    for (const dir of dirs.splice(0)) fs.rmSync(dir, { recursive: true, force: true });
  });

  it('adds empty last name and nick columns; imported clients without a phone stay readable and editable', () => {
    const before = migrationsBeforeClientCard();
    dirs.push(before);
    const sqlite = new Database(':memory:');
    sqlite.pragma('foreign_keys = ON');
    const db = drizzle(sqlite, { schema });
    migrate(db, { migrationsFolder: before });

    const t = 1_790_000_000_000;
    sqlite.exec(`
      INSERT INTO clients (id, name, name_sort, phone, search_text, source, created_at, updated_at) VALUES
        (1, 'Анна Белова', 'анна белова', '+79990000001', 'анна белова 79990000001 89990000001 9990000001', 'yclients', ${t}, ${t}),
        (2, 'Борис', 'борис', NULL, 'борис', 'yclients', ${t}, ${t});
    `);

    migrate(db, { migrationsFolder: MIGRATIONS_DIR });

    expect(sqlite.prepare('SELECT id, last_name, telegram_nick FROM clients ORDER BY id').all()).toEqual([
      { id: 1, last_name: null, telegram_nick: null },
      { id: 2, last_name: null, telegram_nick: null },
    ]);
    expect(clientOut(getClientRow(db, 2))).toMatchObject({ name: 'Борис', lastName: null, phone: null, telegramNick: null });
    expect(searchClients(db, { search: 'белова', archived: false, limit: 10, offset: 0 }).rows.map((r) => r.id)).toEqual([1]);

    const edited = updateClient(db, 2, { phone: null, notes: 'Постоянный клиент', lastName: 'Ёлкин' });
    expect(edited).toMatchObject({ phone: null, notes: 'Постоянный клиент', lastName: 'Ёлкин' });
    expect(searchClients(db, { search: 'елкин', archived: false, limit: 10, offset: 0 }).rows.map((r) => r.id)).toEqual([2]);
    sqlite.close();
  });
});
