import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { appointments } from '../src/db/schema.js';
import { payImportedAppointments } from '../src/scripts/pay-imported-appointments.js';
import { createTestApp, make, type TestApp } from './helpers.js';

const HOUR = 3_600_000;
const NOW = Date.parse('2026-10-18T12:00:00Z');

describe('recording visits carried over from YCLIENTS as paid sales', () => {
  let t: TestApp;
  let client: { id: number };
  let ids: Record<string, number>;

  /** Inserts an appointment the way the YCLIENTS import does: no catalog service, no lines, no sale. */
  const imported = (startsAt: number, status: string, price = 3000, title: string | null = 'Хеликс') =>
    t.ctx.db
      .insert(appointments)
      .values({
        clientId: client.id, masterId: 1, serviceId: null, title, startsAt, endsAt: startsAt + HOUR, status, price,
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
      pastScheduled: imported(NOW - 48 * HOUR, 'scheduled', 2500, null),
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

  const appointment = async (id: number) => (await t.api('GET', `/api/appointments/${id}`)).json();

  it('a dry run counts the past unpaid imported visits and writes nothing', async () => {
    const dry = payImportedAppointments(t.ctx.db, { before: NOW, apply: false });
    expect(dry).toMatchObject({
      matched: 3,
      byStatus: { completed: 1, scheduled: 1, confirmed: 1 },
      total: 5500,
      recorded: 0,
      skippedWithDeposit: [ids.holdingDeposit],
      firstStartsAt: new Date(NOW - 72 * HOUR).toISOString(),
    });
    expect((await t.api('GET', '/api/sales')).json().total).toBe(0);
  });

  it('records one cash sale per visit, dated at its end, and completes the visit; re-running adds nothing', async () => {
    const done = payImportedAppointments(t.ctx.db, { before: NOW, apply: true, now: NOW });
    expect(done.recorded).toBe(2);
    const first = await appointment(ids.pastCompleted);
    expect(first).toMatchObject({ status: 'completed', saleId: expect.any(Number) });
    const sale = (await t.api('GET', `/api/sales/${first.saleId}`)).json();
    expect(sale).toMatchObject({
      number: 1,
      client: { id: client.id },
      employee: { id: 1 },
      appointmentId: ids.pastCompleted,
      shiftId: null,
      total: 3000,
      payments: { cash: 3000, card: 0, transfer: 0, qr: 0, deposit: 0 },
      status: 'completed',
      note: 'Перенесено из YCLIENTS',
      createdAt: new Date(NOW - 71 * HOUR).toISOString(),
    });
    expect(sale.items).toMatchObject([{ type: 'service', name: 'Хеликс', quantity: 1, price: 3000, total: 3000, serviceId: null }]);
    const second = await appointment(ids.pastScheduled);
    expect(second).toMatchObject({ status: 'completed', completedAt: new Date(NOW - 47 * HOUR).toISOString() });
    expect((await t.api('GET', `/api/sales/${second.saleId}`)).json()).toMatchObject({ number: 2, items: [{ name: 'Процедура', price: 2500 }] });
    for (const untouched of ['cancelled', 'future', 'holdingDeposit', 'booked']) {
      expect((await appointment(ids[untouched]!)).saleId).toBeNull();
    }
    // Client stats and reports see the money; the cash register does not.
    expect((await t.api('GET', `/api/clients/${client.id}`)).json().stats.totalSpent).toBe(5500);
    expect(payImportedAppointments(t.ctx.db, { before: NOW, apply: true }).matched).toBe(1);
  });
});
