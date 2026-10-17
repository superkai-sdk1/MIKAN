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
      depositRequired: 2000,
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
      deposit: 0,
      depositRequired: 2000,
      depositStatus: 'waiting',
      depositOperations: [],
      depositLink: null,
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
    const other = await make(t, '/api/clients', { name: 'Пётр', phone: '+79990000104' });
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

describe('appointment service lines', () => {
  let t: TestApp;
  let tattoo: { id: number };
  let piercing: { id: number };
  let client: { id: number };
  const chatId = 555_002;
  const START = '2026-10-17T11:00:00.000Z';

  type Line = { id: number; serviceId: number | null; name: string; category: string | null; price: number; durationMin: number | null };

  const serviceIdColumn = (appointmentId: number) =>
    (t.ctx.sqlite.prepare('SELECT service_id AS serviceId FROM appointments WHERE id = ?').get(appointmentId) as { serviceId: number | null })
      .serviceId;
  const reminders = async () =>
    ((await t.api('GET', '/api/bot/scheduled')).json().items as Array<{ kind: string; status: string; text: string }>).filter(
      (m) => m.kind === 'reminder',
    );

  async function linkTelegram(clientId: number) {
    const url = (await t.api('POST', `/api/clients/${clientId}/telegram-link`)).json().url as string;
    handleStart(t.ctx, { chatId, telegramName: 'Иван', username: 'ivanp' }, new URL(url).searchParams.get('start')!);
  }

  beforeEach(async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(NOW);
    t = await createTestApp();
    tattoo = await make(t, '/api/services', { name: 'Тату среднее', category: 'tattoo', price: 8000, durationMin: 120, aftercareTemplateId: 1 });
    piercing = await make(t, '/api/services', { name: 'Соски', category: 'piercing', price: 2500, durationMin: 45, aftercareTemplateId: 2 });
    client = await make(t, '/api/clients', { name: 'Иван', phone: '+79991234567' });
  });
  afterEach(async () => {
    await t.close();
    vi.useRealTimers();
  });

  it('creates with several services: catalog defaults, custom lines, summed price and duration', async () => {
    const res = await t.api('POST', '/api/appointments', {
      clientId: client.id,
      masterId: 1,
      startsAt: START,
      services: [
        { serviceId: piercing.id },
        { serviceId: tattoo.id, name: 'Тату среднее — рукав', price: 10000, durationMin: 90 },
        { name: '  Подбор украшения ' },
      ],
    });
    expect(res.statusCode).toBe(200);
    const appt = res.json();
    expect(appt.services).toEqual([
      { id: expect.any(Number), serviceId: piercing.id, name: 'Соски', category: 'piercing', price: 2500, durationMin: 45 },
      { id: expect.any(Number), serviceId: tattoo.id, name: 'Тату среднее — рукав', category: 'tattoo', price: 10000, durationMin: 90 },
      { id: expect.any(Number), serviceId: null, name: 'Подбор украшения', category: null, price: 0, durationMin: null },
    ]);
    expect(appt).toMatchObject({
      service: { id: piercing.id, name: 'Соски', category: 'piercing' },
      price: 12500,
      endsAt: '2026-10-17T13:15:00.000Z',
    });
    expect(serviceIdColumn(appt.id)).toBe(piercing.id);
    expect((await t.api('GET', `/api/appointments/${appt.id}`)).json().services).toEqual(appt.services);

    // Explicit price and end win; the legacy `service` is the first line that has a catalog service.
    const custom = await make(t, '/api/appointments', {
      clientId: client.id,
      masterId: 1,
      startsAt: '2026-10-18T11:00:00Z',
      endsAt: '2026-10-18T12:00:00Z',
      price: 9000,
      services: [{ name: 'Консультация', durationMin: 15 }, { serviceId: tattoo.id }],
    });
    expect(custom).toMatchObject({ price: 9000, endsAt: '2026-10-18T12:00:00.000Z', service: { id: tattoo.id } });
    expect(serviceIdColumn(custom.id)).toBe(tattoo.id);

    const none = await make(t, '/api/appointments', {
      clientId: client.id, masterId: 1, startsAt: '2026-10-19T11:00:00Z', services: [{ name: 'Консультация', durationMin: 30 }],
    });
    expect(none).toMatchObject({ service: null, price: 0, endsAt: '2026-10-19T11:30:00.000Z' });
    expect(serviceIdColumn(none.id)).toBeNull();
  });

  it('validates service lines and stores nothing on failure', async () => {
    const post = (services: unknown, extra: object = {}) =>
      t.api('POST', '/api/appointments', { clientId: client.id, masterId: 1, startsAt: START, services, ...extra });
    expect((await post([{ price: 100, durationMin: 30 }])).json().error.message).toBe('Позиция №1: укажите название услуги');
    expect((await post([{ name: 'Консультация', durationMin: 30 }, { name: '   ' }])).json().error.message).toBe(
      'Позиция №2: укажите название услуги',
    );
    const missing = await post([{ serviceId: 999 }]);
    expect(missing.statusCode).toBe(400);
    expect(missing.json().error.message).toBe('Услуга не найдена');
    expect((await post([{ name: 'X', price: -1 }])).json().error.message).toBe('«Цена (№1)»: должно быть не меньше 0');
    expect((await post([{ name: 'X', durationMin: 0 }])).json().error.message).toBe('«Длительность (№1)»: должно быть не меньше 1');
    const tooMany = await post(Array.from({ length: 21 }, (_, i) => ({ name: `Позиция ${i}`, durationMin: 10 })));
    expect(tooMany.json().error.message).toBe('«Услуги»: не больше 20 элементов');
    expect((await post([{ name: 'Без длительности' }])).json().error.message).toBe('«Окончание»: обязательное поле');
    expect((await t.api('GET', '/api/appointments')).json().items).toEqual([]);
    expect(t.ctx.sqlite.prepare('SELECT count(*) AS n FROM appointment_services').get()).toEqual({ n: 0 });
  });

  it('PATCH replaces, keeps or clears the lines; price follows the lines unless set', async () => {
    const appt = await make(t, '/api/appointments', {
      clientId: client.id, masterId: 1, startsAt: START, services: [{ serviceId: tattoo.id }, { name: 'Подбор украшения', price: 500 }],
    });
    expect(appt.price).toBe(8500);
    const ids = appt.services.map((l: Line) => l.id);
    const patch = async (payload: object) => {
      const res = await t.api('PATCH', `/api/appointments/${appt.id}`, payload);
      expect(res.statusCode).toBe(200);
      return res.json();
    };

    const notes = await patch({ notes: 'Эскиз согласован' });
    expect(notes.services.map((l: Line) => l.id)).toEqual(ids);
    expect(notes.price).toBe(8500);

    // Re-sending the same lines keeps the stored rows (stable ids for the history).
    const same = await patch({
      services: [{ serviceId: tattoo.id, name: 'Тату среднее', price: 8000, durationMin: 120 }, { name: 'Подбор украшения', price: 500 }],
    });
    expect(same.services.map((l: Line) => l.id)).toEqual(ids);

    const replaced = await patch({ services: [{ serviceId: piercing.id }] });
    expect(replaced.services).toEqual([
      { id: expect.any(Number), serviceId: piercing.id, name: 'Соски', category: 'piercing', price: 2500, durationMin: 45 },
    ]);
    expect(replaced).toMatchObject({ price: 2500, service: { id: piercing.id }, endsAt: '2026-10-17T13:00:00.000Z' });
    expect(serviceIdColumn(appt.id)).toBe(piercing.id);

    const custom = await patch({ services: [{ name: 'Коррекция' }], price: 3000 });
    expect(custom).toMatchObject({ price: 3000, service: null, services: [{ serviceId: null, name: 'Коррекция', price: 0 }] });
    expect(serviceIdColumn(appt.id)).toBeNull();

    const cleared = await patch({ services: [] });
    expect(cleared).toMatchObject({ services: [], service: null, price: 0 });
    expect(t.ctx.sqlite.prepare('SELECT count(*) AS n FROM appointment_services').get()).toEqual({ n: 0 });

    // `services: null` means "absent": nothing changes.
    expect((await patch({ services: null, price: 1000 })).services).toEqual([]);
  });

  it('legacy serviceId: creates one line; the same service keeps the lines, another replaces them, null clears them', async () => {
    const legacy = await make(t, '/api/appointments', { clientId: client.id, masterId: 1, serviceId: tattoo.id, startsAt: START, price: 7000 });
    expect(legacy.services).toEqual([
      { id: expect.any(Number), serviceId: tattoo.id, name: 'Тату среднее', category: 'tattoo', price: 7000, durationMin: 120 },
    ]);
    expect(legacy).toMatchObject({ price: 7000, endsAt: '2026-10-17T13:00:00.000Z', service: { id: tattoo.id } });
    expect((await t.api('POST', '/api/appointments', { clientId: client.id, masterId: 1, serviceId: 999, startsAt: START })).json().error.message).toBe(
      'Услуга не найдена',
    );

    const appt = await make(t, '/api/appointments', {
      clientId: client.id,
      masterId: 1,
      startsAt: '2026-10-18T11:00:00Z',
      services: [{ name: 'Подбор украшения', price: 500 }, { serviceId: tattoo.id, price: 9000 }],
    });
    const ids = appt.services.map((l: Line) => l.id);
    const patch = async (payload: object) => (await t.api('PATCH', `/api/appointments/${appt.id}`, payload)).json();

    // An older build re-sends the service it shows (the first catalog line): the lines stay as they are.
    const kept = await patch({ serviceId: tattoo.id, price: 9500, notes: 'Старое приложение' });
    expect(kept.services.map((l: Line) => l.id)).toEqual(ids);
    expect(kept).toMatchObject({ price: 9500, service: { id: tattoo.id } });

    const replaced = await patch({ serviceId: piercing.id, price: 3000 });
    expect(replaced.services).toEqual([
      { id: expect.any(Number), serviceId: piercing.id, name: 'Соски', category: 'piercing', price: 3000, durationMin: 45 },
    ]);
    expect(replaced).toMatchObject({ price: 3000, service: { id: piercing.id } });

    const defaults = await patch({ serviceId: tattoo.id });
    expect(defaults.services).toMatchObject([{ serviceId: tattoo.id, price: 8000 }]);
    expect(defaults.price).toBe(3000);

    const cleared = await patch({ serviceId: null });
    expect(cleared).toMatchObject({ services: [], service: null, price: 3000 });
    expect(serviceIdColumn(appt.id)).toBeNull();

    // `services` wins over the legacy field.
    const both = await patch({ serviceId: tattoo.id, services: [{ serviceId: piercing.id }] });
    expect(both).toMatchObject({ service: { id: piercing.id }, services: [{ serviceId: piercing.id }] });
  });

  it('legacy serviceId: null keeps custom-only lines (older builds always send it)', async () => {
    const appt = await make(t, '/api/appointments', {
      clientId: client.id, masterId: 1, startsAt: START, endsAt: '2026-10-17T12:00:00Z',
      services: [{ name: 'Коррекция бровей', price: 1000 }],
    });
    const res = await t.api('PATCH', `/api/appointments/${appt.id}`, { serviceId: null, notes: 'Старое приложение' });
    expect(res.json()).toMatchObject({ services: [{ serviceId: null, name: 'Коррекция бровей', price: 1000 }], notes: 'Старое приложение' });
  });

  it('a price-only edit (older builds) moves a single line that carried the old total along with it', async () => {
    const appt = await make(t, '/api/appointments', {
      clientId: client.id, masterId: 1, startsAt: START, services: [{ serviceId: tattoo.id, price: 5000 }],
    });
    const lineId = appt.services[0].id;
    const repriced = (await t.api('PATCH', `/api/appointments/${appt.id}`, { serviceId: tattoo.id, price: 4000 })).json();
    expect(repriced).toMatchObject({ price: 4000, services: [{ id: lineId, serviceId: tattoo.id, price: 4000 }] });
    expect((await t.api('PATCH', `/api/appointments/${appt.id}`, { price: 4500 })).json().services).toMatchObject([{ id: lineId, price: 4500 }]);

    // A line priced apart from the total, or several lines, are left alone.
    const apart = await make(t, '/api/appointments', {
      clientId: client.id, masterId: 1, startsAt: '2026-10-18T11:00:00Z', price: 6000, services: [{ serviceId: tattoo.id, price: 5000 }],
    });
    const apartPatched = (await t.api('PATCH', `/api/appointments/${apart.id}`, { serviceId: tattoo.id, price: 4000 })).json();
    expect(apartPatched).toMatchObject({ price: 4000, services: [{ price: 5000 }] });
    const multi = await make(t, '/api/appointments', {
      clientId: client.id, masterId: 1, startsAt: '2026-10-19T11:00:00Z', services: [{ serviceId: tattoo.id }, { name: 'Подбор украшения', price: 500 }],
    });
    const multiPatched = (await t.api('PATCH', `/api/appointments/${multi.id}`, { price: 7000 })).json();
    expect(multiPatched.price).toBe(7000);
    expect(multiPatched.services.map((l: Line) => l.price)).toEqual([8000, 500]);
  });

  it('reminders name every booked service and are refreshed when the lines change', async () => {
    await linkTelegram(client.id);
    const appt = await make(t, '/api/appointments', {
      clientId: client.id, masterId: 1, startsAt: START, services: [{ serviceId: tattoo.id }, { name: 'Подбор украшения' }],
    });
    let list = await reminders();
    expect(list).toHaveLength(1);
    expect(list[0]!.text).toContain('Услуги: Тату среднее, Подбор украшения');

    await t.api('PATCH', `/api/appointments/${appt.id}`, { notes: 'Без изменений в услугах' });
    expect(await reminders()).toHaveLength(1);

    await t.api('PATCH', `/api/appointments/${appt.id}`, { services: [{ serviceId: piercing.id }] });
    list = await reminders();
    expect(list.map((m) => m.status)).toEqual(['cancelled', 'pending']);
    expect(list[1]!.text).toContain('Услуга: Соски');
    expect(list[1]!.text).not.toContain('Тату');

    const titled = await make(t, '/api/appointments', {
      clientId: client.id, masterId: 1, title: 'Консультация по эскизу', startsAt: '2026-10-18T11:00:00Z', endsAt: '2026-10-18T12:00:00Z',
    });
    const forTitled = (await reminders()).filter((m) => m.status === 'pending' && m.text.includes('Консультация по эскизу'));
    expect(forTitled).toHaveLength(1);
    expect(forTitled[0]!.text).toContain('Услуга: Консультация по эскизу');
    expect(titled.services).toEqual([]);
  });

  it('complete picks the aftercare template of the first line whose service has one', async () => {
    await linkTelegram(client.id);
    const consult = await make(t, '/api/services', { name: 'Консультация', category: 'other', price: 0, durationMin: 15 });
    const appt = await make(t, '/api/appointments', {
      clientId: client.id,
      masterId: 1,
      startsAt: '2026-10-15T06:00:00Z',
      services: [{ name: 'Подбор украшения' }, { serviceId: consult.id }, { serviceId: piercing.id }, { serviceId: tattoo.id }],
    });
    expect(appt.service.id).toBe(consult.id);
    const res = await t.api('POST', `/api/appointments/${appt.id}/complete`, { sendAftercare: true });
    expect(res.statusCode).toBe(200);
    expect(res.json().scheduledMessages).toBe(6);
    const aftercare = ((await t.api('GET', '/api/bot/scheduled')).json().items as Array<{ kind: string; text: string }>).filter(
      (m) => m.kind === 'aftercare',
    );
    expect(aftercare[0]!.text).toMatch(/^MIKAN STUDIO · уход после процедуры\n\nПрокол сделан!/);
  });
});
