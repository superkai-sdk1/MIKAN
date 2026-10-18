import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { appointments, appointmentServices } from '../src/db/schema.js';
import { payImportedAppointments } from '../src/scripts/pay-imported-appointments.js';
import { createTestApp, make, type TestApp } from './helpers.js';

const HOUR = 3_600_000;
const NOW = Date.parse('2026-10-18T12:00:00Z');
/** The studio started working in MIKAN here: later visits were made in the app. */
const CUTOFF = NOW - 20 * HOUR;

describe('recording visits carried over from YCLIENTS as paid sales', () => {
  let t: TestApp;
  let client: { id: number };
  let ids: Record<string, number>;
  let lobeId: number;
  let helixId: number;

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

  /** YCLIENTS visits often came with their services: lines with catalog services, the first mirrored. */
  const withServices = (startsAt: number, price: number, lines: Array<{ serviceId: number; name: string; price: number }>) => {
    const id = imported(startsAt, 'completed', price, null);
    t.ctx.db.update(appointments).set({ serviceId: lines[0]!.serviceId }).where(eq(appointments.id, id)).run();
    t.ctx.db
      .insert(appointmentServices)
      .values(lines.map((l, position) => ({ appointmentId: id, serviceId: l.serviceId, name: l.name, price: l.price, durationMin: 30, position })))
      .run();
    return id;
  };

  beforeEach(async () => {
    t = await createTestApp();
    client = await make(t, '/api/clients', { name: 'Иван', phone: '+79991234567' });
    const service = await make(t, '/api/services', { name: 'Мочка', category: 'piercing', price: 2000, durationMin: 30 });
    const helix = await make(t, '/api/services', { name: 'Хеликс', category: 'piercing', price: 2500, durationMin: 30 });
    lobeId = service.id;
    helixId = helix.id;
    ids = {
      withLines: withServices(NOW - 60 * HOUR, 4500, [
        { serviceId: service.id, name: 'Мочка', price: 2000 },
        { serviceId: helix.id, name: 'Хеликс', price: 2500 },
      ]),
      discounted: withServices(NOW - 50 * HOUR, 4000, [
        { serviceId: service.id, name: 'Мочка', price: 2500 },
        { serviceId: helix.id, name: 'Хеликс', price: 2500 },
      ]),
      noShow: imported(NOW - 40 * HOUR, 'no_show'),
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
    const dry = payImportedAppointments(t.ctx.db, { before: CUTOFF, apply: false });
    expect(dry).toMatchObject({
      matched: 5,
      byStatus: { completed: 3, scheduled: 1, confirmed: 1 },
      total: 14000,
      recorded: 0,
      skippedWithDeposit: [ids.holdingDeposit],
      firstStartsAt: new Date(NOW - 72 * HOUR).toISOString(),
    });
    expect((await t.api('GET', '/api/sales')).json().total).toBe(0);
  });

  it('records one cash sale per visit, dated at its end, and completes the visit; re-running adds nothing', async () => {
    const done = payImportedAppointments(t.ctx.db, { before: CUTOFF, apply: true, now: NOW });
    expect(done.recorded).toBe(4);
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
    expect((await t.api('GET', `/api/sales/${second.saleId}`)).json()).toMatchObject({ number: 4, items: [{ name: 'Процедура', price: 2500 }] });

    // A visit with its services: one item per service, so the analytics sees each service.
    const lines = (await t.api('GET', `/api/sales/${(await appointment(ids.withLines!)).saleId}`)).json();
    expect(lines).toMatchObject({ number: 2, subtotal: 4500, discount: 0, total: 4500, payments: { cash: 4500 } });
    expect(lines.items).toMatchObject([
      { type: 'service', serviceId: lobeId, name: 'Мочка', quantity: 1, price: 2000, total: 2000 },
      { type: 'service', serviceId: helixId, name: 'Хеликс', quantity: 1, price: 2500, total: 2500 },
    ]);
    // Lines worth more than the visit price: the difference is the discount.
    const discounted = (await t.api('GET', `/api/sales/${(await appointment(ids.discounted!)).saleId}`)).json();
    expect(discounted).toMatchObject({ number: 3, subtotal: 5000, discount: 1000, total: 4000, payments: { cash: 4000 } });
    expect(discounted.items).toHaveLength(2);

    for (const untouched of ['cancelled', 'noShow', 'future', 'holdingDeposit', 'booked']) {
      expect((await appointment(ids[untouched]!)).saleId).toBeNull();
    }
    // Client stats and reports see the money; the cash register does not.
    expect((await t.api('GET', `/api/clients/${client.id}`)).json().stats.totalSpent).toBe(14000);
    expect(payImportedAppointments(t.ctx.db, { before: CUTOFF, apply: true }).matched).toBe(1);
  });
});
