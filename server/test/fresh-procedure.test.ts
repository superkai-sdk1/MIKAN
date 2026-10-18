import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import Database from 'better-sqlite3';
import { eq } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { MIGRATIONS_DIR } from '../src/db/client.js';
import * as schema from '../src/db/schema.js';
import { clients, scheduledMessages } from '../src/db/schema.js';
import { createTestApp, make, type TestApp } from './helpers.js';

/** Seeded aftercare templates: 1 — tattoo, 2 — piercing. */
const TATTOO_TEMPLATE = 1;
const PIERCING_TEMPLATE = 2;

describe('«Свежий прокол / Свежее тату»: aftercare memos only for fresh procedures', () => {
  let t: TestApp;
  let client: { id: number };

  beforeEach(async () => {
    t = await createTestApp();
    client = await make(t, '/api/clients', { name: 'Иван', phone: '+79991234567' });
    t.ctx.db.update(clients).set({ telegramChatId: 555_001 }).where(eq(clients.id, client.id)).run();
  });
  afterEach(async () => {
    await t.close();
  });

  const service = (body: object) => make(t, '/api/services', { category: 'piercing', price: 2000, durationMin: 30, ...body });
  const book = (services: Array<{ id: number }>, startsAt: string) =>
    make(t, '/api/appointments', { clientId: client.id, masterId: 1, services: services.map((s) => ({ serviceId: s.id })), startsAt });
  const complete = async (appointmentId: number, body: object = {}) =>
    (await t.api('POST', `/api/appointments/${appointmentId}/complete`, { sendAftercare: true, ...body })).json();
  const memosOf = (appointmentId: number) =>
    t.ctx.db.select().from(scheduledMessages).where(eq(scheduledMessages.appointmentId, appointmentId)).all().filter((m) => m.kind === 'aftercare');

  it('stores the switch; older builds get it from whether the service has its own memo template', async () => {
    expect(await service({ name: 'Хеликс', aftercareTemplateId: PIERCING_TEMPLATE })).toMatchObject({ freshProcedure: true });
    expect(await service({ name: 'Замена украшения' })).toMatchObject({ freshProcedure: false });
    const explicit = await service({ name: 'Мочка', freshProcedure: true });
    expect(explicit.freshProcedure).toBe(true);
    const off = await t.api('PATCH', `/api/services/${explicit.id}`, { freshProcedure: false });
    expect(off.json().freshProcedure).toBe(false);
    // A PATCH from an older build (no field) keeps it.
    expect((await t.api('PATCH', `/api/services/${explicit.id}`, { price: 2500 })).json().freshProcedure).toBe(false);
  });

  it('sends no memo for a service with the switch off, even when the app asks for a template', async () => {
    const swap = await service({ name: 'Замена украшения', aftercareTemplateId: PIERCING_TEMPLATE, freshProcedure: false });
    const appt = await book([swap], '2026-10-20T10:00:00Z');
    const done = await complete(appt.id, { aftercareTemplateId: PIERCING_TEMPLATE });
    expect(done.scheduledMessages).toBe(0);
    expect(done.appointment.status).toBe('completed');
    expect(memosOf(appt.id)).toHaveLength(0);
  });

  it('a visit with a fresh procedure gets the memo of that procedure, not of the extras', async () => {
    const swap = await service({ name: 'Замена украшения', aftercareTemplateId: TATTOO_TEMPLATE, freshProcedure: false });
    const helix = await service({ name: 'Хеликс', aftercareTemplateId: PIERCING_TEMPLATE, freshProcedure: true });
    const appt = await book([swap, helix], '2026-10-20T10:00:00Z');
    const done = await complete(appt.id);
    expect(done.scheduledMessages).toBeGreaterThan(0);
    const piercingSteps = (await t.api('GET', '/api/aftercare-templates')).json().items.find((x: { id: number }) => x.id === PIERCING_TEMPLATE).steps;
    expect(memosOf(appt.id)).toHaveLength(piercingSteps.length);
  });

  it('a fresh procedure without its own template uses the template the app chose', async () => {
    const tattoo = await service({ name: 'Мини тату', category: 'tattoo', freshProcedure: true });
    const appt = await book([tattoo], '2026-10-20T10:00:00Z');
    expect((await complete(appt.id)).scheduledMessages).toBe(0);

    const second = await book([tattoo], '2026-10-21T10:00:00Z');
    expect((await complete(second.id, { aftercareTemplateId: TATTOO_TEMPLATE })).scheduledMessages).toBeGreaterThan(0);
  });

  it('an appointment without catalog services gets no memo', async () => {
    const appt = await make(t, '/api/appointments', {
      clientId: client.id, masterId: 1, title: 'Коррекция', startsAt: '2026-10-20T10:00:00Z', endsAt: '2026-10-20T11:00:00Z',
    });
    expect((await complete(appt.id, { aftercareTemplateId: TATTOO_TEMPLATE })).scheduledMessages).toBe(0);
  });
});

describe('migration 0008_service_fresh_procedure', () => {
  const dirs: string[] = [];
  afterEach(() => {
    for (const dir of dirs.splice(0)) fs.rmSync(dir, { recursive: true, force: true });
  });

  it('marks the services that have their own memo template as fresh procedures', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mikan-migrations-'));
    dirs.push(dir);
    fs.cpSync(MIGRATIONS_DIR, dir, { recursive: true });
    const journalPath = path.join(dir, 'meta', '_journal.json');
    const journal = JSON.parse(fs.readFileSync(journalPath, 'utf8')) as { entries: Array<{ tag: string }> };
    journal.entries = journal.entries.filter((e) => e.tag < '0008');
    fs.writeFileSync(journalPath, JSON.stringify(journal));

    const sqlite = new Database(':memory:');
    sqlite.pragma('foreign_keys = ON');
    const db = drizzle(sqlite, { schema });
    migrate(db, { migrationsFolder: dir });
    const now = 1_790_000_000_000;
    sqlite.exec(`
      INSERT INTO aftercare_templates (id, name, category, steps_json, created_at, updated_at) VALUES (1, 'Пирсинг', 'piercing', '[]', ${now}, ${now});
      INSERT INTO services (id, name, category, price, duration_min, aftercare_template_id, created_at, updated_at) VALUES
        (1, 'Хеликс', 'piercing', 3000, 30, 1, ${now}, ${now}),
        (2, 'Замена украшения', 'piercing', 300, 15, NULL, ${now}, ${now});
    `);
    migrate(db, { migrationsFolder: MIGRATIONS_DIR });
    expect(sqlite.prepare('SELECT id, fresh_procedure FROM services ORDER BY id').all()).toEqual([
      { id: 1, fresh_procedure: 1 },
      { id: 2, fresh_procedure: 0 },
    ]);
    sqlite.close();
  });
});
