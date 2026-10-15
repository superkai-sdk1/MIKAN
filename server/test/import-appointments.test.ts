import { describe, expect, it } from 'vitest';
import { asc, eq } from 'drizzle-orm';
import { openDatabase } from '../src/db/client.js';
import { appointments, clients, employees, scheduledMessages } from '../src/db/schema.js';
import { createClient } from '../src/domain/clients.js';
import {
  importAppointments,
  loginFor,
  PLACEHOLDER_CLIENT_NAME,
  type VisitImportRecord,
} from '../src/scripts/import-appointments.js';

const NOW = Date.parse('2026-10-15T12:00:00Z');
const opts = { apply: true, source: 'yclients' };

function seededDb() {
  const { db } = openDatabase(':memory:');
  createClient(db, { name: 'Анна', phone: '+79990000001', source: 'yclients' });
  createClient(db, { name: 'Борис', phone: null, notes: '⚠️ Неполный номер в YCLIENTS: 7999000 — уточните у клиента.', source: 'yclients' });
  return db;
}

const visits: VisitImportRecord[] = [
  { masterName: 'Амина', clientName: 'Анна', clientPhone: '79990000001', startsAt: '2026-10-10T12:00:00+03:00', durationMin: 30, status: 'completed', title: 'Хеликс', price: 1800, notes: null, createdAt: '2026-10-01T10:00:00+03:00' },
  { masterName: 'Амина', clientName: 'Борис', clientPhone: '7999000', startsAt: '2026-10-16T15:00:00+03:00', durationMin: 120, status: 'scheduled', title: 'ТАТУ', price: 8000, notes: 'эскиз согласован', createdAt: null },
  { masterName: 'Медея', clientName: null, clientPhone: null, startsAt: '2024-01-20T13:00:00+03:00', durationMin: 30, status: 'completed', title: 'Прокол мочки', price: 2500, notes: null, createdAt: null },
  { masterName: 'Медея', clientName: 'Новый Клиент', clientPhone: '79990000009', startsAt: '2024-02-01T13:00:00+03:00', durationMin: 30, status: 'cancelled', title: null, price: 0, notes: null, createdAt: null },
];

describe('importAppointments', () => {
  it('transliterates master names into logins', () => {
    expect(loginFor('Амина')).toBe('amina');
    expect(loginFor('Муха')).toBe('mukha');
    expect(loginFor('Медея')).toBe('medeya');
  });

  it('writes nothing in dry-run mode but reports masters and clients it would create', () => {
    const db = seededDb();

    const summary = importAppointments(db, visits, { ...opts, apply: false }, NOW);

    expect(summary).toMatchObject({ total: 4, created: 4, existing: 0, clientsMatched: 2, clientsCreated: 1, placeholderVisits: 1, invalid: [] });
    expect(summary.mastersCreated).toEqual([
      { name: 'Амина', login: 'amina', active: true },
      { name: 'Медея', login: 'medeya', active: false },
    ]);
    expect(db.select().from(appointments).all()).toHaveLength(0);
    expect(db.select().from(employees).all()).toHaveLength(0);
  });

  it('creates masters, matches clients by phone and by the incomplete-number note, and keeps history statuses', () => {
    const db = seededDb();

    importAppointments(db, visits, opts, NOW);

    const masters = db.select().from(employees).orderBy(asc(employees.id)).all();
    expect(masters.map((m) => [m.name, m.login, m.isMaster, m.active])).toEqual([
      ['Амина', 'amina', true, true],
      ['Медея', 'medeya', true, false],
    ]);
    const rows = db.select().from(appointments).orderBy(asc(appointments.id)).all();
    expect(rows.map((r) => r.status)).toEqual(['completed', 'scheduled', 'completed', 'cancelled']);
    expect(rows[0]).toMatchObject({ clientId: 1, price: 1800, title: 'Хеликс', createdAt: Date.parse('2026-10-01T07:00:00Z') });
    expect(rows[0]?.completedAt).toBe(rows[0]?.endsAt);
    expect(rows[1]).toMatchObject({ clientId: 2, completedAt: null });
    expect(rows[1]!.endsAt - rows[1]!.startsAt).toBe(120 * 60_000);
    const placeholder = db.select().from(clients).where(eq(clients.name, PLACEHOLDER_CLIENT_NAME)).get();
    expect(placeholder?.botEnabled).toBe(false);
    expect(rows[2]?.clientId).toBe(placeholder?.id);
    const created = db.select().from(clients).where(eq(clients.name, 'Новый Клиент')).get();
    expect(created?.phone).toBe('+79990000009');
    expect(db.select().from(scheduledMessages).all()).toHaveLength(0);
  });

  it('keeps different visits in the same slot: a cancelled booking and its re-booking, two walk-ins', () => {
    const db = seededDb();
    const slot = { masterName: 'Амина', startsAt: '2026-10-12T14:00:00+03:00', durationMin: 30, price: 1800, notes: null, createdAt: null };
    const sameSlot: VisitImportRecord[] = [
      { ...slot, clientName: 'Анна', clientPhone: '79990000001', status: 'cancelled', title: 'Хеликс' },
      { ...slot, clientName: 'Анна', clientPhone: '79990000001', status: 'completed', title: 'Хеликс' },
      { ...slot, clientName: null, clientPhone: null, status: 'completed', title: 'Прокол мочки' },
      { ...slot, clientName: null, clientPhone: null, status: 'completed', title: 'Пупок' },
    ];

    const summary = importAppointments(db, sameSlot, opts, NOW);

    expect(summary).toMatchObject({ created: 4, existing: 0 });
    expect(db.select().from(appointments).all()).toHaveLength(4);
  });

  it('is idempotent: a second run creates nothing new', () => {
    const db = seededDb();
    importAppointments(db, visits, opts, NOW);

    const second = importAppointments(db, visits, opts, NOW);

    expect(second).toMatchObject({ created: 0, existing: 4, clientsCreated: 0, mastersCreated: [] });
    expect(db.select().from(appointments).all()).toHaveLength(4);
    expect(db.select().from(clients).all()).toHaveLength(4);
  });
});
