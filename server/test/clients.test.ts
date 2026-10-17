import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { handleStart } from '../src/bot/onboarding.js';
import { storeMessage } from '../src/domain/bot-chats.js';
import { createTestApp, make, type TestApp } from './helpers.js';

describe('clients', () => {
  let t: TestApp;
  beforeEach(async () => {
    t = await createTestApp();
  });
  afterEach(async () => {
    await t.close();
  });

  it('creates a client with a normalized phone and full shape', async () => {
    const res = await t.api('POST', '/api/clients', {
      name: '  Иван Петров ',
      phone: '8 (999) 123-45-67',
      instagram: '@ivan.p',
      birthday: '1995-04-12',
      notes: 'Аллергия на никель',
      source: 'instagram',
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({
      name: 'Иван Петров',
      phone: '+79991234567',
      instagram: 'ivan.p',
      birthday: '1995-04-12',
      notes: 'Аллергия на никель',
      source: 'instagram',
      telegramLinked: false,
      telegramUsername: null,
      botEnabled: true,
      archived: false,
      stats: { visits: 0, totalSpent: 0, lastVisitAt: null, upcomingAppointments: 0 },
    });
  });

  it('rejects a phone that belongs to another client, naming that client', async () => {
    await make(t, '/api/clients', { name: 'Иван Петров', phone: '+79991234567' });
    const dup = await t.api('POST', '/api/clients', { name: 'Другой', phone: '89991234567' });
    expect(dup.statusCode).toBe(409);
    expect(dup.json().error).toEqual({
      code: 'conflict',
      message: 'Телефон +79991234567 уже принадлежит клиенту «Иван Петров»',
    });
    const other = await make(t, '/api/clients', { name: 'Пётр', phone: '+79990000201' });
    const patch = await t.api('PATCH', `/api/clients/${other.id}`, { phone: '9991234567' });
    expect(patch.statusCode).toBe(409);
  });

  it('validates input', async () => {
    expect((await t.api('POST', '/api/clients', { name: '' })).statusCode).toBe(400);
    const bad = await t.api('POST', '/api/clients', { name: 'X', phone: '+79990000202', birthday: '12.04.1995' });
    expect(bad.json().error.message).toBe('«Дата рождения»: дата должна быть в формате ГГГГ-ММ-ДД');
    expect((await t.api('GET', '/api/clients/999')).statusCode).toBe(404);
  });

  it('searches by name (Cyrillic, case-insensitive), phone digits, instagram; sorted by name; paginated', async () => {
    await make(t, '/api/clients', { name: 'Яна Смирнова', phone: '+79990000001', instagram: 'yana_tattoo' });
    await make(t, '/api/clients', { name: 'анна Кузнецова', phone: '+79990000002' });
    await make(t, '/api/clients', { name: 'Борис Ёлкин', phone: '+12025550143' });
    const archived = await make(t, '/api/clients', { name: 'Архивный', phone: '+79990000203' });
    await t.api('PATCH', `/api/clients/${archived.id}`, { archived: true });

    const names = async (q: string) =>
      (await t.api('GET', `/api/clients${q}`)).json().items.map((c: { name: string }) => c.name);
    expect(await names('')).toEqual(['анна Кузнецова', 'Борис Ёлкин', 'Яна Смирнова']);
    expect(await names('?search=АННА')).toEqual(['анна Кузнецова']);
    expect(await names('?search=елкин')).toEqual(['Борис Ёлкин']);
    expect(await names(`?search=${encodeURIComponent('8999000000')}`)).toEqual(['анна Кузнецова', 'Яна Смирнова']);
    expect(await names(`?search=${encodeURIComponent('+7 (999) 000-00-02')}`)).toEqual(['анна Кузнецова']);
    expect(await names('?search=yana_')).toEqual(['Яна Смирнова']);
    expect(await names('?archived=true')).toEqual(['Архивный']);

    const page = await t.api('GET', '/api/clients?limit=2&offset=1');
    expect(page.json().total).toBe(3);
    expect(page.json().items).toHaveLength(2);
    expect(page.json().items[0].stats).toBeNull();
    expect((await t.api('GET', '/api/clients?limit=500')).statusCode).toBe(400);
  });

  it('updates, clears fields, and returns history and stats', async () => {
    const c = await make(t, '/api/clients', { name: 'Иван', phone: '+79990000204', instagram: 'ivan', botEnabled: false });
    const patched = await t.api('PATCH', `/api/clients/${c.id}`, { instagram: null, notes: 'VIP', botEnabled: true });
    expect(patched.json()).toMatchObject({ instagram: null, notes: 'VIP', botEnabled: true, name: 'Иван' });
    const history = await t.api('GET', `/api/clients/${c.id}/history`);
    expect(history.json()).toEqual({ items: [], appointments: [], sales: [] });
    expect((await t.api('GET', '/api/clients/999/history')).statusCode).toBe(404);
  });

  it('issues a Telegram deep link with the bot username', async () => {
    const c = await make(t, '/api/clients', { name: 'Иван', phone: '+79990000205' });
    const res = await t.api('POST', `/api/clients/${c.id}/telegram-link`);
    expect(res.statusCode).toBe(200);
    expect(res.json().url).toMatch(/^https:\/\/t\.me\/mikan_test_bot\?start=c[A-Za-z0-9_-]{16}$/);
    t.gateway.usernameValue = null;
    const off = await t.api('POST', `/api/clients/${c.id}/telegram-link`);
    expect(off.statusCode).toBe(409);
  });

  it('finds the client\'s Telegram chat (null when there is none) and follows a relink', async () => {
    const chatId = 700_001;
    const link = async (clientId: number) => {
      const url = (await t.api('POST', `/api/clients/${clientId}/telegram-link`)).json().url as string;
      handleStart(t.ctx, { chatId, telegramName: 'Иван', username: 'ivanp' }, new URL(url).searchParams.get('start')!);
    };
    const chatOf = async (clientId: number) => (await t.api('GET', `/api/clients/${clientId}/chat`)).json().chat;

    const ivan = await make(t, '/api/clients', { name: 'Иван', phone: '+79990000206' });
    const olga = await make(t, '/api/clients', { name: 'Ольга', phone: '+79990000207' });
    expect((await t.api('GET', `/api/clients/${ivan.id}/chat`)).json()).toEqual({ chat: null });

    await link(ivan.id);
    storeMessage(t.ctx.db, chatId, 'user', 'Здравствуйте', { bumpUnread: true });
    expect(await chatOf(ivan.id)).toMatchObject({
      chatId,
      client: { id: ivan.id, name: 'Иван', telegramLinked: true },
      telegramName: 'Иван',
      username: 'ivanp',
      unreadCount: 1,
      lastMessage: { role: 'user', text: 'Здравствуйте' },
    });

    // The same Telegram account linked to another client moves the chat over.
    await link(olga.id);
    expect(await chatOf(ivan.id)).toBeNull();
    expect((await chatOf(olga.id)).client.id).toBe(olga.id);

    // A chat attributed to the client without a linked chat id is still found.
    t.ctx.sqlite.prepare('UPDATE clients SET telegram_chat_id = NULL WHERE id = ?').run(olga.id);
    expect((await chatOf(olga.id)).chatId).toBe(chatId);

    expect((await t.api('GET', '/api/clients/999/chat')).statusCode).toBe(404);
  });
});
