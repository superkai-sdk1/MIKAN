import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { appointments } from '../src/db/schema.js';
import { closeImportedAppointments } from '../src/scripts/close-imported-appointments.js';
import { createTestApp, make, type TestApp } from './helpers.js';

const HOUR = 3_600_000;
const NOW = Date.parse('2026-10-18T12:00:00Z');

describe('closing visits carried over from YCLIENTS as paid', () => {
  let t: TestApp;
  let client: { id: number };
  let ids: Record<string, number>;

  /** Inserts an appointment the way the YCLIENTS import does: no catalog service, no lines, no sale. */
  const imported = (startsAt: number, status: string, price = 3000) =>
    t.ctx.db
      .insert(appointments)
      .values({
        clientId: client.id, masterId: 1, serviceId: null, title: 'Хеликс', startsAt, endsAt: startsAt + HOUR, status, price,
        depositRequired: 0, notes: null, saleId: null, completedAt: status === 'completed' ? startsAt + HOUR : null,
        createdAt: startsAt - 24 * HOUR, updatedAt: startsAt,
      })
      .returning()
      .get().id;

  beforeEach(async () => {
    t = await createTestApp();
    client = await make(t, '/api/clients', { name: 'Иван', phone: '+79991234567' });
    const service = await make(t, '/api/services', { name: 'Мочка', category: 'piercing', price: 2000, durationMin: 30 });
    ids = {
      pastCompleted: imported(NOW - 72 * HOUR, 'completed'),
      pastScheduled: imported(NOW - 48 * HOUR, 'scheduled', 2500),
      cancelled: imported(NOW - 24 * HOUR, 'cancelled'),
      future: imported(NOW + 24 * HOUR, 'scheduled'),
      holdingDeposit: imported(NOW - 30 * HOUR, 'confirmed'),
      booked: (await make(t, '/api/appointments', { clientId: client.id, masterId: 1, serviceId: service.id, startsAt: new Date(NOW - 10 * HOUR).toISOString() })).id,
    };
    await t.api('POST', `/api/appointments/${ids.holdingDeposit}/deposit`, { amount: 1000, method: 'transfer' });
  });
  afterEach(async () => {
    await t.close();
  });

  const statusOf = async (id: number) => (await t.api('GET', `/api/appointments/${id}`)).json();

  it('a dry run counts the past unpaid imported visits and changes nothing', () => {
    const dry = closeImportedAppointments(t.ctx.db, { before: NOW, apply: false });
    expect(dry).toMatchObject({
      matched: 3,
      byStatus: { completed: 1, scheduled: 1, confirmed: 1 },
      totalPrice: 5500,
      closed: 0,
      skippedWithDeposit: [ids.holdingDeposit],
      firstStartsAt: new Date(NOW - 72 * HOUR).toISOString(),
    });
  });

  it('closes them as completed and paid outside MIKAN; MIKAN then refuses a second payment', async () => {
    const done = closeImportedAppointments(t.ctx.db, { before: NOW, apply: true, now: NOW });
    expect(done.closed).toBe(2);
    expect(await statusOf(ids.pastCompleted)).toMatchObject({ status: 'completed', paidOutside: true, saleId: null });
    expect(await statusOf(ids.pastScheduled)).toMatchObject({
      status: 'completed',
      paidOutside: true,
      completedAt: new Date(NOW - 47 * HOUR).toISOString(),
    });
    for (const untouched of ['cancelled', 'future', 'holdingDeposit', 'booked']) {
      expect((await statusOf(ids[untouched]!)).paidOutside).toBe(false);
    }
    const pay = await t.api('POST', '/api/sales', {
      appointmentId: ids.pastCompleted,
      items: [{ type: 'service', name: 'Хеликс', price: 3000 }],
      discount: 0,
      payments: { cash: 3000, deposit: 0 },
    });
    expect(pay.statusCode).toBe(409);
    expect(pay.json().error.message).toBe('Запись уже оплачена до перехода на MIKAN (перенесена из YCLIENTS)');
    expect(closeImportedAppointments(t.ctx.db, { before: NOW, apply: true }).matched).toBe(1);
  });
});
