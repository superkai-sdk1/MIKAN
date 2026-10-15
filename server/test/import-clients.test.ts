import { describe, expect, it } from 'vitest';
import { asc } from 'drizzle-orm';
import { openDatabase } from '../src/db/client.js';
import { clients } from '../src/db/schema.js';
import { importClients, type ImportRecord } from '../src/scripts/import-clients.js';

const records: ImportRecord[] = [
  { name: 'Тест Один', phone: '89990000001', birthday: '1995-04-12', notes: 'Из YCLIENTS: визитов 2.', createdAt: '2024-03-12T10:00:00+03:00' },
  { name: 'Тест Два', phone: '79990000002', birthday: null, notes: 'Из YCLIENTS: визитов не было.', createdAt: null },
  { name: 'Без Номера', phone: null, birthday: null, notes: '⚠️ Неполный номер в YCLIENTS: 7999000 — уточните у клиента.', createdAt: null },
];

const allClients = (db: ReturnType<typeof openDatabase>['db']) => db.select().from(clients).orderBy(asc(clients.id)).all();

describe('importClients', () => {
  it('writes nothing in dry-run mode but reports what would be created', () => {
    const { db } = openDatabase(':memory:');

    const summary = importClients(db, records, { apply: false, source: 'yclients' });

    expect(summary).toMatchObject({ total: 3, created: 3, existing: 0, duplicateInFile: 0, invalid: [] });
    expect(allClients(db)).toHaveLength(0);
  });

  it('creates clients with normalized phones, source and the original first-visit date', () => {
    const { db } = openDatabase(':memory:');

    importClients(db, records, { apply: true, source: 'yclients' });

    const rows = allClients(db);
    expect(rows.map((r) => r.phone)).toEqual(['+79990000001', '+79990000002', null]);
    expect(rows.every((r) => r.source === 'yclients' && r.botEnabled && !r.archived)).toBe(true);
    expect(rows[0]?.birthday).toBe('1995-04-12');
    expect(rows[0]?.createdAt).toBe(Date.parse('2024-03-12T07:00:00Z'));
    expect(rows[0]?.searchText).toContain('9990000001');
  });

  it('is idempotent: a second run skips existing clients, including phone-less ones', () => {
    const { db } = openDatabase(':memory:');
    importClients(db, records, { apply: true, source: 'yclients' });

    const second = importClients(db, records, { apply: true, source: 'yclients' });

    expect(second).toMatchObject({ created: 0, existing: 3 });
    expect(allClients(db)).toHaveLength(3);
  });

  it('skips phone duplicates inside the file and reports invalid rows without aborting the rest', () => {
    const { db } = openDatabase(':memory:');
    const input = [
      ...records,
      { ...records[0], name: 'Дубль' },
      { name: '', phone: null, birthday: null, notes: null, createdAt: null },
      { name: 'Плохая Дата', phone: null, birthday: '31-12-1990', notes: null, createdAt: null },
    ];

    const summary = importClients(db, input, { apply: true, source: 'yclients' });

    expect(summary).toMatchObject({ total: 6, created: 3, duplicateInFile: 1 });
    expect(summary.invalid.map((i) => i.index)).toEqual([4, 5]);
    expect(allClients(db)).toHaveLength(3);
  });
});
