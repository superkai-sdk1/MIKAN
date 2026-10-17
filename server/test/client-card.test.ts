import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildClientContext } from '../src/bot/prompt.js';
import { clients } from '../src/db/schema.js';
import { cleanTelegramNick, createClient } from '../src/domain/clients.js';
import { clientFullName } from '../src/lib/serialize.js';
import { createTestApp, make, type TestApp } from './helpers.js';

describe('client card: last name, Telegram nick, required phone', () => {
  let t: TestApp;
  beforeEach(async () => {
    t = await createTestApp();
  });
  afterEach(async () => {
    await t.close();
  });

  /** A client imported from YCLIENTS without a phone (the app can no longer create these). */
  const importedWithoutPhone = () => createClient(t.ctx.db, { name: 'Борис', phone: null, source: 'yclients' });

  it('creates a client with last name and Telegram nick', async () => {
    const res = await t.api('POST', '/api/clients', {
      name: ' Иван ',
      lastName: ' Петров ',
      phone: '8 999 123-45-67',
      telegramNick: 'https://t.me/Ivan_Petrov/',
      birthday: '1995-04-12',
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({
      name: 'Иван',
      lastName: 'Петров',
      phone: '+79991234567',
      telegramNick: 'Ivan_Petrov',
      birthday: '1995-04-12',
      instagram: null,
      telegramUsername: null,
    });
    const minimal = await make(t, '/api/clients', { name: 'Анна', phone: '+79990000002' });
    expect(minimal).toMatchObject({ lastName: null, telegramNick: null, birthday: null });
  });

  it('requires a phone for new clients', async () => {
    for (const phone of [undefined, null, '', '   ']) {
      const res = await t.api('POST', '/api/clients', { name: 'Без телефона', phone });
      expect(res.statusCode).toBe(400);
      expect(res.json().error).toEqual({ code: 'validation_error', message: '«Телефон»: обязательное поле' });
    }
    expect((await t.api('POST', '/api/clients', { name: 'X', phone: '12' })).json().error.message).toBe(
      '«Телефон»: некорректный номер телефона',
    );
  });

  it('validates the Telegram nick', async () => {
    const bad = await t.api('POST', '/api/clients', { name: 'Иван', phone: '+79991234567', telegramNick: 'иван петров' });
    expect(bad.statusCode).toBe(400);
    expect(bad.json().error.message).toBe('«Ник в Telegram»: латинские буквы, цифры и «_», от 4 до 32 символов (например, @ivan_petrov)');
    expect((await t.api('POST', '/api/clients', { name: 'Иван', phone: '+79991234567', telegramNick: '@abc' })).statusCode).toBe(400);
    expect((await t.api('POST', '/api/clients', { name: 'Иван', phone: '+79991234567', telegramNick: '@' })).json().telegramNick).toBeNull();
  });

  it('changes but never removes a phone that is set', async () => {
    const c = await make(t, '/api/clients', { name: 'Иван', phone: '+79991234567' });
    const cleared = await t.api('PATCH', `/api/clients/${c.id}`, { phone: null });
    expect(cleared.statusCode).toBe(400);
    expect(cleared.json().error.message).toBe('«Телефон»: обязательное поле — номер можно изменить, но не удалить');
    expect((await t.api('PATCH', `/api/clients/${c.id}`, { phone: '' })).statusCode).toBe(400);
    const changed = await t.api('PATCH', `/api/clients/${c.id}`, { phone: '89990000003' });
    expect(changed.json().phone).toBe('+79990000003');
  });

  it('keeps clients imported without a phone readable and editable', async () => {
    const legacy = importedWithoutPhone();
    expect((await t.api('GET', `/api/clients/${legacy.id}`)).json()).toMatchObject({ name: 'Борис', lastName: null, phone: null });
    // What an older app sends: every field, with `phone: null` for the empty phone field.
    const old = await t.api('PATCH', `/api/clients/${legacy.id}`, {
      name: 'Борис', phone: null, instagram: null, birthday: null, notes: 'Постоянный клиент', source: 'yclients', botEnabled: true,
    });
    expect(old.statusCode).toBe(200);
    expect(old.json()).toMatchObject({ notes: 'Постоянный клиент', phone: null });
    // The new app sends the new fields too.
    const current = await t.api('PATCH', `/api/clients/${legacy.id}`, { lastName: 'Ёлкин', telegramNick: '@boris_e' });
    expect(current.json()).toMatchObject({ name: 'Борис', lastName: 'Ёлкин', telegramNick: 'boris_e', phone: null });
    expect((await t.api('PATCH', `/api/clients/${legacy.id}`, { archived: true })).statusCode).toBe(200);
  });

  it('clears the last name and nick with null and keeps them when omitted', async () => {
    const c = await make(t, '/api/clients', { name: 'Иван', lastName: 'Петров', phone: '+79991234567', telegramNick: 'ivan_p' });
    const kept = await t.api('PATCH', `/api/clients/${c.id}`, { notes: 'VIP' });
    expect(kept.json()).toMatchObject({ lastName: 'Петров', telegramNick: 'ivan_p' });
    const cleared = await t.api('PATCH', `/api/clients/${c.id}`, { lastName: '', telegramNick: null });
    expect(cleared.json()).toMatchObject({ lastName: null, telegramNick: null });
  });

  it('searches by last name and Telegram nick and sorts by the full name', async () => {
    await make(t, '/api/clients', { name: 'Анна', lastName: 'Яковлева', phone: '+79990000001' });
    await make(t, '/api/clients', { name: 'Анна', lastName: 'Белова', phone: '+79990000002', telegramNick: 'anna_tattoo' });
    await make(t, '/api/clients', { name: 'Пётр', lastName: 'Ёлкин', phone: '+79990000003' });
    const names = async (q: string) =>
      (await t.api('GET', `/api/clients${q}`)).json().items.map((c: { name: string; lastName: string | null }) => clientFullName(c));
    expect(await names('')).toEqual(['Анна Белова', 'Анна Яковлева', 'Пётр Ёлкин']);
    expect(await names('?search=елкин')).toEqual(['Пётр Ёлкин']);
    expect(await names(`?search=${encodeURIComponent('анна бел')}`)).toEqual(['Анна Белова']);
    expect(await names('?search=ANNA_TAT')).toEqual(['Анна Белова']);

    // A changed last name moves the client in search results.
    const petr = (await t.api('GET', '/api/clients?search=елкин')).json().items[0];
    await t.api('PATCH', `/api/clients/${petr.id}`, { lastName: 'Смирнов' });
    expect(await names('?search=смирнов')).toEqual(['Пётр Смирнов']);
    expect(await names('?search=елкин')).toEqual([]);
  });

  it('embeds the last name in ClientRef and names the full client in conflicts and the bot', async () => {
    const ivan = await make(t, '/api/clients', { name: 'Иван', lastName: 'Петров', phone: '+79991234567' });
    const appointment = await make(t, '/api/appointments', { clientId: ivan.id, masterId: 1, startsAt: '2026-10-17T11:00:00Z', endsAt: '2026-10-17T12:00:00Z' });
    expect(appointment.client).toEqual({ id: ivan.id, name: 'Иван', lastName: 'Петров', phone: '+79991234567', telegramLinked: false });

    const dup = await t.api('POST', '/api/clients', { name: 'Другой', phone: '+79991234567' });
    expect(dup.json().error.message).toBe('Телефон +79991234567 уже принадлежит клиенту «Иван Петров»');

    const other = await make(t, '/api/clients', { name: 'Анна', phone: '+79990000002' });
    const clash = await t.api('POST', '/api/appointments', { clientId: other.id, masterId: 1, startsAt: '2026-10-17T11:30:00Z', endsAt: '2026-10-17T12:30:00Z' });
    expect(clash.json().error.message).toMatch(/^У мастера уже есть запись в это время: Иван Петров, /);

    const row = t.ctx.db.select().from(clients).where(eq(clients.id, ivan.id)).get()!;
    expect(buildClientContext(t.ctx.db, Date.now(), row, null)).toContain('Клиент: Иван Петров, телефон +79991234567.');
  });
});

describe('client name helpers', () => {
  it('joins first and last name, skipping blanks', () => {
    expect(clientFullName({ name: 'Иван', lastName: 'Петров' })).toBe('Иван Петров');
    expect(clientFullName({ name: 'Иван Петров', lastName: null })).toBe('Иван Петров');
    expect(clientFullName({ name: ' Иван ', lastName: '  ' })).toBe('Иван');
  });

  it('cleans Telegram nicks from @ and links', () => {
    expect(cleanTelegramNick('@ivan_p')).toBe('ivan_p');
    expect(cleanTelegramNick(' t.me/ivan_p ')).toBe('ivan_p');
    expect(cleanTelegramNick('https://telegram.me/ivan_p/')).toBe('ivan_p');
    expect(cleanTelegramNick('')).toBeNull();
    expect(cleanTelegramNick(null)).toBeNull();
    expect(cleanTelegramNick(undefined)).toBeUndefined();
  });
});
