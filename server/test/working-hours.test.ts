import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildStablePrompt } from '../src/bot/prompt.js';
import { settings } from '../src/db/schema.js';
import { DEFAULT_STUDIO, workdayFromText } from '../src/domain/settings.js';
import { formatTimeOfDay, parseTimeOfDay } from '../src/lib/time.js';
import { createTestApp, make, type TestApp } from './helpers.js';

describe('studio working hours', () => {
  let t: TestApp;
  beforeEach(async () => {
    t = await createTestApp();
  });
  afterEach(async () => {
    await t.close();
  });

  /** Stores studio settings the way a server without workdayStart / workdayEnd saved them. */
  function storeLegacyStudio(workingHours: string) {
    const { workdayStart: _start, workdayEnd: _end, ...legacy } = { ...DEFAULT_STUDIO, workingHours };
    t.ctx.db.update(settings).set({ value: JSON.stringify(legacy) }).where(eq(settings.key, 'studio')).run();
  }

  it('saves the opening and closing time, normalizing hours to two digits', async () => {
    const put = await t.api('PUT', '/api/settings/studio', { workdayStart: '9:30', workdayEnd: '24:00' });
    expect(put.statusCode).toBe(200);
    expect(put.json()).toMatchObject({ workdayStart: '09:30', workdayEnd: '24:00' });
    expect((await t.api('GET', '/api/settings/studio')).json()).toMatchObject({ workdayStart: '09:30', workdayEnd: '24:00' });
  });

  it('keeps the hours when an older app saves settings without them', async () => {
    await t.api('PUT', '/api/settings/studio', { workdayStart: '10:00', workdayEnd: '20:00' });
    const old = await t.api('PUT', '/api/settings/studio', { name: 'MIKAN', workingHours: 'Без выходных' });
    expect(old.json()).toMatchObject({ name: 'MIKAN', workingHours: 'Без выходных', workdayStart: '10:00', workdayEnd: '20:00' });
  });

  it('rejects malformed times and a day that ends before it starts', async () => {
    const malformed = await t.api('PUT', '/api/settings/studio', { workdayStart: '25:00' });
    expect(malformed.statusCode).toBe(400);
    expect(malformed.json().error.message).toBe('«Начало рабочего дня»: время должно быть в формате ЧЧ:ММ (например, 10:00)');
    expect((await t.api('PUT', '/api/settings/studio', { workdayEnd: '21:60' })).statusCode).toBe(400);
    expect((await t.api('PUT', '/api/settings/studio', { workdayEnd: 'вечер' })).statusCode).toBe(400);

    const reversed = await t.api('PUT', '/api/settings/studio', { workdayStart: '21:00', workdayEnd: '10:00' });
    expect(reversed.statusCode).toBe(400);
    expect(reversed.json().error.message).toBe('Конец рабочего дня (10:00) должен быть позже начала (21:00)');
    // Checked against the stored value too: only the end is sent here.
    const endOnly = await t.api('PUT', '/api/settings/studio', { workdayEnd: '11:00' });
    expect(endOnly.statusCode).toBe(400);
    expect((await t.api('GET', '/api/settings/studio')).json()).toMatchObject({ workdayStart: '11:00', workdayEnd: '21:00' });
  });

  it('derives the hours of settings saved before they existed from the working-hours text', async () => {
    storeLegacyStudio('Пн–Вс с 10:00 до 20:30');
    expect((await t.api('GET', '/api/settings/studio')).json()).toMatchObject({ workdayStart: '10:00', workdayEnd: '20:30' });
    storeLegacyStudio('По записи');
    expect((await t.api('GET', '/api/settings/studio')).json()).toMatchObject({ workdayStart: '11:00', workdayEnd: '21:00' });
    // The first save stores the derived hours, so later reads no longer depend on the text.
    storeLegacyStudio('Ежедневно 9:00–22:00');
    await t.api('PUT', '/api/settings/studio', { workingHours: 'Без выходных' });
    expect((await t.api('GET', '/api/settings/studio')).json()).toMatchObject({ workdayStart: '09:00', workdayEnd: '22:00' });
  });

  it('accepts appointments outside working hours — the studio may open early or stay late', async () => {
    await t.api('PUT', '/api/settings/studio', { workdayStart: '10:00', workdayEnd: '21:00' });
    const client = await make(t, '/api/clients', { name: 'Иван', phone: '+79991234567' });
    // Europe/Moscow is UTC+3: 07:00–08:00 and 22:30–23:30 studio time.
    const early = await t.api('POST', '/api/appointments', {
      clientId: client.id, masterId: 1, startsAt: '2026-10-17T04:00:00Z', endsAt: '2026-10-17T05:00:00Z',
    });
    expect(early.statusCode).toBe(200);
    const late = await t.api('POST', '/api/appointments', {
      clientId: client.id, masterId: 1, startsAt: '2026-10-17T19:30:00Z', endsAt: '2026-10-17T20:30:00Z',
    });
    expect(late.statusCode).toBe(200);
    const moved = await t.api('PATCH', `/api/appointments/${early.json().id}`, { startsAt: '2026-10-17T03:00:00Z', endsAt: '2026-10-17T04:00:00Z' });
    expect(moved.statusCode).toBe(200);
  });

  it('tells the bot the hours when the free-text working hours are empty', async () => {
    await t.api('PUT', '/api/settings/studio', { workingHours: null, workdayStart: '10:00', workdayEnd: '20:00' });
    expect(buildStablePrompt(t.ctx.db)).toContain('Часы работы: 10:00–20:00');
    await t.api('PUT', '/api/settings/studio', { workingHours: 'Пн–Сб 10:00–20:00, вс выходной' });
    expect(buildStablePrompt(t.ctx.db)).toContain('Часы работы: Пн–Сб 10:00–20:00, вс выходной');
  });
});

describe('time of day helpers', () => {
  it('parses HH:MM between 00:00 and 24:00', () => {
    expect(parseTimeOfDay('00:00')).toBe(0);
    expect(parseTimeOfDay('9:05')).toBe(545);
    expect(parseTimeOfDay(' 21:30 ')).toBe(1290);
    expect(parseTimeOfDay('24:00')).toBe(1440);
    for (const bad of ['24:01', '12:60', '1230', '12:3', '', 'abc']) expect(parseTimeOfDay(bad)).toBeNull();
    expect(formatTimeOfDay(545)).toBe('09:05');
    expect(formatTimeOfDay(1440)).toBe('24:00');
  });

  it('finds a valid range in free text', () => {
    expect(workdayFromText('Ежедневно 11:00–21:00')).toEqual({ workdayStart: '11:00', workdayEnd: '21:00' });
    expect(workdayFromText('9:00 - 18:00, сб до 16:00')).toEqual({ workdayStart: '09:00', workdayEnd: '18:00' });
    expect(workdayFromText('с 12:00 до 23:00')).toEqual({ workdayStart: '12:00', workdayEnd: '23:00' });
    expect(workdayFromText('22:00–02:00')).toEqual({ workdayStart: '11:00', workdayEnd: '21:00' });
    expect(workdayFromText('')).toEqual({ workdayStart: '11:00', workdayEnd: '21:00' });
  });
});
