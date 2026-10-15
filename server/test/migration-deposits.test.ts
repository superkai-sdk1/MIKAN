import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import Database from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';
import { afterEach, describe, expect, it } from 'vitest';
import { MIGRATIONS_DIR } from '../src/db/client.js';
import * as schema from '../src/db/schema.js';

/** A copy of the migrations folder that stops before `0005_deposits`. */
function migrationsBeforeDeposits(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mikan-migrations-'));
  fs.cpSync(MIGRATIONS_DIR, dir, { recursive: true });
  const journalPath = path.join(dir, 'meta', '_journal.json');
  const journal = JSON.parse(fs.readFileSync(journalPath, 'utf8')) as { entries: Array<{ tag: string }> };
  journal.entries = journal.entries.filter((e) => e.tag < '0005');
  fs.writeFileSync(journalPath, JSON.stringify(journal));
  return dir;
}

describe('migration 0005_deposits', () => {
  const dirs: string[] = [];
  afterEach(() => {
    for (const dir of dirs.splice(0)) fs.rmSync(dir, { recursive: true, force: true });
  });

  it('keeps the legacy prepayment of open unpaid appointments as held money and rebuilds qr_payments', () => {
    const before = migrationsBeforeDeposits();
    dirs.push(before);
    const sqlite = new Database(':memory:');
    sqlite.pragma('foreign_keys = ON');
    const db = drizzle(sqlite, { schema });
    migrate(db, { migrationsFolder: before });

    const t = 1_790_000_000_000;
    sqlite.exec(`
      INSERT INTO employees (id, name, login, password_hash, color, created_at, updated_at) VALUES (1, 'Анна', 'anna', 'x', '#FF7A1A', ${t}, ${t});
      INSERT INTO clients (id, name, name_sort, created_at, updated_at) VALUES (1, 'Иван', 'иван', ${t}, ${t});
      INSERT INTO sales (id, number, employee_id, subtotal, total, pay_transfer, status, created_at) VALUES (1, 1, 1, 8000, 8000, 8000, 'completed', ${t});
      INSERT INTO appointments (id, client_id, master_id, starts_at, ends_at, status, price, deposit, sale_id, created_at, updated_at) VALUES
        (1, 1, 1, ${t}, ${t + 1}, 'scheduled', 8000, 2000, NULL, ${t}, ${t + 10}),
        (2, 1, 1, ${t}, ${t + 1}, 'completed', 8000, 1000, NULL, ${t}, ${t + 20}),
        (3, 1, 1, ${t}, ${t + 1}, 'completed', 8000, 3000, 1, ${t}, ${t + 30}),
        (4, 1, 1, ${t}, ${t + 1}, 'cancelled', 8000, 500, NULL, ${t}, ${t + 40}),
        (5, 1, 1, ${t}, ${t + 1}, 'confirmed', 8000, 0, NULL, ${t}, ${t + 50});
      INSERT INTO qr_payments (id, provider, external_id, payload, amount, status, sale_input_json, sale_id, employee_id, expires_at, created_at, updated_at)
        VALUES (7, 'tochka', 'AS1', 'https://qr.nspk.ru/AS1', 8000, 'paid', '{}', 1, 1, ${t}, ${t}, ${t});
    `);

    migrate(db, { migrationsFolder: MIGRATIONS_DIR });

    expect(sqlite.prepare('SELECT appointment_id, type, amount, method, employee_id, created_at FROM deposit_operations ORDER BY appointment_id').all()).toEqual([
      { appointment_id: 1, type: 'receive', amount: 2000, method: 'transfer', employee_id: null, created_at: t + 10 },
      { appointment_id: 2, type: 'receive', amount: 1000, method: 'transfer', employee_id: null, created_at: t + 20 },
    ]);
    expect(sqlite.prepare('SELECT id, deposit_required FROM appointments ORDER BY id').all()).toEqual([
      { id: 1, deposit_required: 2000 },
      { id: 2, deposit_required: 1000 },
      { id: 3, deposit_required: 3000 },
      { id: 4, deposit_required: 500 },
      { id: 5, deposit_required: 0 },
    ]);
    const columns = (sqlite.prepare('PRAGMA table_info(appointments)').all() as Array<{ name: string }>).map((c) => c.name);
    expect(columns).not.toContain('deposit');
    expect(sqlite.prepare('SELECT id, kind, appointment_id, sale_input_json, sale_id, sent_at FROM qr_payments').all()).toEqual([
      { id: 7, kind: 'sale', appointment_id: null, sale_input_json: '{}', sale_id: 1, sent_at: null },
    ]);
    expect(sqlite.prepare('SELECT pay_deposit FROM sales').get()).toEqual({ pay_deposit: 0 });
    expect(sqlite.prepare('PRAGMA foreign_key_check').all()).toEqual([]);
    sqlite.close();
  });
});
