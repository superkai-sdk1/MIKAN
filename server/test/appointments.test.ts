import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { handleStart } from '../src/bot/onboarding.js';
import { createTestApp, make, type TestApp } from './helpers.js';

const NOW = Date.parse('2026-10-15T09:00:00.000Z'); // Thu 12:00 Moscow

describe('appointments, reminders and aftercare', () => {
  let t: TestApp;
  let service: { id: number };
  let client: { id: number };
  const chatId = 555_001;

  async function linkTelegram(clientId: number, chat = chatId) {
    const url = (await t.api('POST', `/api/clients/${clientId}/telegram-link`)).json().url as string;
    const payload = new URL(url).searchParams.get('start')!;
    handleStart(t.ctx, { chatId: chat, telegramName: 'Иван', username: 'ivanp' }, payload);
  }

  const scheduled = async (status?: string) =>
    (await t.api('GET', `/api/bot/scheduled${status ? `?status=${status}` : ''}`)).json().items as Array<Record<string, unknown>>;

  beforeEach(async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(NOW);
    t = await createTestApp();
    service = await make(t, '/api/services', {
      name: 'Тату среднее',
      category: 'tattoo',
      price: 8000,
      priceFrom: true,
      durationMin: 120,
      aftercareTemplateId: 1,
    });
    client = await make(t, '/api/clients', { name: 'Иван', phone: '+79991234567' });
  });
  afterEach(async () => {
    await t.close();
    vi.useRealTimers();
  });

  it('creates an appointment with defaults from the service and a reminder for a linked client', async () => {
    await linkTelegram(client.id);
    const res = await t.api('POST', '/api/appointments', {
      clientId: client.id,
      masterId: 1,
      serviceId: service.id,
      title: 'Тату на предплечье',
      startsAt: '2026-10-17T11:00:00.000Z',
      deposit: 2000,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({
      client: { id: client.id, name: 'Иван', phone: '+79991234567', telegramLinked: true },
      master: { id: 1, name: 'Админ', color: '#FF7A1A' },
      service: { id: service.id, name: 'Тату среднее', category: 'tattoo' },
      title: 'Тату на предплечье',
      startsAt: '2026-10-17T11:00:00.000Z',
      endsAt: '2026-10-17T13:00:00.000Z',
      status: 'scheduled',
      price: 8000,
      deposit: 2000,
      saleId: null,
      completedAt: null,
    });
    const pending = await scheduled('pending');
    expect(pending).toHaveLength(1);
    expect(pending[0]).toMatchObject({
      kind: 'reminder',
      chatId,
      appointmentId: res.json().id,
      sendAt: '2026-10-16T11:00:00.000Z',
      status: 'pending',
      client: { id: client.id, telegramLinked: true },
    });
    expect(pending[0]!.text).toContain('Когда: суббота, 17 октября в 14:00');
    expect(pending[0]!.text).toContain('Услуга: Тату среднее');
  });

  it('detects overlaps per master (409 schedule_conflict) unless forced; ignores cancelled', async () => {
    const first = await make(t, '/api/appointments', { clientId: client.id, masterId: 1, serviceId: service.id, startsAt: '2026-10-17T11:00:00Z' });
    const other = await make(t, '/api/clients', { name: 'Пётр' });
    const clash = await t.api('POST', '/api/appointments', {
      clientId: other.id,
      masterId: 1,
      startsAt: '2026-10-17T12:00:00Z',
      endsAt: '2026-10-17T12:30:00Z',
    });
    expect(clash.statusCode).toBe(409);
    expect(clash.json().error).toEqual({
      code: 'schedule_conflict',
      message: 'У мастера уже есть запись в это время: Иван, 17.10.2026 14:00–16:00',
    });
    const forced = await t.api('POST', '/api/appointments', {
      clientId: other.id, masterId: 1, startsAt: '2026-10-17T12:00:00Z', endsAt: '2026-10-17T12:30:00Z', force: true,
    });
    expect(forced.statusCode).toBe(200);
    const adjacent = await t.api('POST', '/api/appointments', {
      clientId: other.id, masterId: 1, startsAt: '2026-10-17T13:00:00Z', endsAt: '2026-10-17T14:00:00Z',
    });
    expect(adjacent.statusCode).toBe(200);

    await t.api('PATCH', `/api/appointments/${first.id}`, { status: 'cancelled' });
    await t.api('PATCH', `/api/appointments/${forced.json().id}`, { status: 'no_show' });
    const free = await t.api('POST', '/api/appointments', {
      clientId: other.id, masterId: 1, startsAt: '2026-10-17T11:30:00Z', endsAt: '2026-10-17T12:30:00Z',
    });
    expect(free.statusCode).toBe(200);

    const bad = await t.api('POST', '/api/appointments', { clientId: other.id, masterId: 1, startsAt: '2026-10-17T11:00:00Z', endsAt: '2026-10-17T10:00:00Z' });
    expect(bad.json().error.message).toBe('Окончание записи должно быть позже начала');
    const noEnd = await t.api('POST', '/api/appointments', { clientId: other.id, masterId: 1, startsAt: '2026-10-17T11:00:00Z' });
    expect(noEnd.json().error.message).toBe('«Окончание»: обязательное поле');
    expect((await t.api('POST', '/api/appointments', { clientId: 999, masterId: 1, startsAt: '2026-10-17T11:00:00Z', endsAt: '2026-10-17T12:00:00Z' })).statusCode).toBe(400);

    const day = await t.api('GET', '/api/appointments?from=2026-10-17T11:15:00Z&to=2026-10-17T12:15:00Z&masterId=1');
    expect(day.json().items.map((a: { id: number }) => a.id)).toEqual([first.id, free.json().id, forced.json().id]);
    const onlyActive = await t.api('GET', '/api/appointments?status=scheduled,confirmed');
    expect(onlyActive.json().items.every((a: { status: string }) => a.status === 'scheduled')).toBe(true);
    expect((await t.api('GET', '/api/appointments?status=bogus')).statusCode).toBe(400);
    expect((await t.api('GET', '/api/appointments/999')).statusCode).toBe(404);
  });

  it('replaces the reminder on reschedule and cancels it on cancellation', async () => {
    await linkTelegram(client.id);
    const appt = await make(t, '/api/appointments', { clientId: client.id, masterId: 1, serviceId: service.id, startsAt: '2026-10-17T11:00:00Z' });
    const moved = await t.api('PATCH', `/api/appointments/${appt.id}`, { startsAt: '2026-10-18T11:00:00Z' });
    expect(moved.json()).toMatchObject({ startsAt: '2026-10-18T11:00:00.000Z', endsAt: '2026-10-18T13:00:00.000Z' });
    const all = await scheduled();
    expect(all.map((m) => [m.status, m.sendAt])).toEqual([
      ['cancelled', '2026-10-16T11:00:00.000Z'],
      ['pending', '2026-10-17T11:00:00.000Z'],
    ]);
    await t.api('PATCH', `/api/appointments/${appt.id}`, { notes: 'Эскиз согласован' });
    expect(await scheduled('pending')).toHaveLength(1);
    await t.api('PATCH', `/api/appointments/${appt.id}`, { status: 'cancelled' });
    expect(await scheduled('pending')).toHaveLength(0);

    // Too close to the start → no reminder.
    const soon = await make(t, '/api/appointments', { clientId: client.id, masterId: 1, startsAt: '2026-10-15T15:00:00Z', endsAt: '2026-10-15T16:00:00Z' });
    expect((await scheduled('pending')).filter((m) => m.appointmentId === soon.id)).toHaveLength(0);
  });

  it('completes: writes consumable usage, schedules aftercare at studio-local times, cancels the reminder', async () => {
    await linkTelegram(client.id);
    const needle = await make(t, '/api/products', { kind: 'consumable', name: 'Картридж', price: 0, initialQuantity: 10 });
    const appt = await make(t, '/api/appointments', { clientId: client.id, masterId: 1, serviceId: service.id, startsAt: '2026-10-17T17:00:00Z' });
    expect(await scheduled('pending')).toHaveLength(1);

    vi.setSystemTime(Date.parse('2026-10-17T20:30:00.000Z')); // 23:30 Moscow
    const res = await t.api('POST', `/api/appointments/${appt.id}/complete`, {
      sendAftercare: true,
      consumables: [{ productId: needle.id, quantity: 2 }],
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().scheduledMessages).toBe(6);
    expect(res.json().appointment).toMatchObject({ status: 'completed', completedAt: '2026-10-17T20:30:00.000Z' });

    const moves = (await t.api('GET', `/api/products/${needle.id}/movements`)).json().items;
    expect(moves[0]).toMatchObject({ type: 'usage', delta: -2, quantityAfter: 8, appointmentId: appt.id });

    const after = (await scheduled()).filter((m) => m.kind === 'aftercare');
    expect(after.map((m) => m.sendAt)).toEqual([
      '2026-10-17T20:35:00.000Z',
      '2026-10-18T09:00:00.000Z',
      '2026-10-20T09:00:00.000Z',
      '2026-10-24T09:00:00.000Z',
      '2026-10-31T09:00:00.000Z',
      '2026-11-16T09:00:00.000Z',
    ]);
    expect(after[0]!.text).toMatch(/^MIKAN STUDIO · уход после процедуры\n\nТатуировка готова!/);
    expect(after[1]!.text).toMatch(/^MIKAN STUDIO · уход, день 1\n\n/);
    expect((await scheduled()).find((m) => m.kind === 'reminder')!.status).toBe('cancelled');

    // Regression (review #4): a retried/double-tapped complete must not deduct consumables again.
    const again = await t.api('POST', `/api/appointments/${appt.id}/complete`, {
      sendAftercare: true,
      consumables: [{ productId: needle.id, quantity: 2 }],
    });
    expect(again.statusCode).toBe(200);
    expect(again.json().scheduledMessages).toBe(0);
    expect((await t.api('GET', `/api/products/${needle.id}`)).json().quantity).toBe(8);
    expect((await t.api('GET', `/api/clients/${client.id}`)).json().stats).toMatchObject({
      visits: 1,
      lastVisitAt: '2026-10-17T17:00:00.000Z',
    });
  });

  it('skips aftercare for unlinked or bot-disabled clients, and rolls back on insufficient consumables', async () => {
    const appt = await make(t, '/api/appointments', { clientId: client.id, masterId: 1, serviceId: service.id, startsAt: '2026-10-15T10:00:00Z' });
    const res = await t.api('POST', `/api/appointments/${appt.id}/complete`, { sendAftercare: true });
    expect(res.json().scheduledMessages).toBe(0);

    await linkTelegram(client.id);
    await t.api('PATCH', `/api/clients/${client.id}`, { botEnabled: false });
    const appt2 = await make(t, '/api/appointments', { clientId: client.id, masterId: 1, serviceId: service.id, startsAt: '2026-10-15T13:00:00Z' });
    expect((await t.api('POST', `/api/appointments/${appt2.id}/complete`, { sendAftercare: true })).json().scheduledMessages).toBe(0);

    const needle = await make(t, '/api/products', { kind: 'consumable', name: 'Игла', price: 0, initialQuantity: 1 });
    const appt3 = await make(t, '/api/appointments', { clientId: client.id, masterId: 1, startsAt: '2026-10-16T10:00:00Z', endsAt: '2026-10-16T11:00:00Z' });
    const fail = await t.api('POST', `/api/appointments/${appt3.id}/complete`, { sendAftercare: false, consumables: [{ productId: needle.id, quantity: 3 }] });
    expect(fail.statusCode).toBe(409);
    expect(fail.json().error.code).toBe('insufficient_stock');
    expect((await t.api('GET', `/api/appointments/${appt3.id}`)).json().status).toBe('scheduled');

    await t.api('PATCH', `/api/appointments/${appt3.id}`, { status: 'cancelled' });
    expect((await t.api('POST', `/api/appointments/${appt3.id}/complete`, { sendAftercare: false })).statusCode).toBe(409);
    expect((await t.api('POST', `/api/appointments/${appt3.id}/complete`, { sendAftercare: true, aftercareTemplateId: 999 })).statusCode).toBe(409);
  });
});
