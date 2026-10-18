import type Anthropic from '@anthropic-ai/sdk';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { handleContact, handleStaffCommand, handleStart } from '../src/bot/onboarding.js';
import { BotPipeline, REPLIES } from '../src/bot/pipeline.js';
import { issueStaffCode } from '../src/bot/staff.js';
import { STAFF_TOOLS } from '../src/bot/staff-tools.js';
import { getStaffChatId } from '../src/domain/settings.js';
import { createTestApp, make, message, ScriptedAi, text, toolUse, type TestApp } from './helpers.js';

const NOW = Date.parse('2026-10-15T09:00:00.000Z'); // Thu 12:00 Moscow
const CHAT = 740_001;
const STAFF = -740;
const from = { chatId: CHAT, telegramName: 'Анна', username: 'anna_m' };
const STAFF_TOOL_NAMES = ['today', 'appointments', 'client_info', 'analytics', 'stock'];

describe('bot: staff recognised by phone, staff mode', () => {
  let t: TestApp;
  let ai: ScriptedAi;
  let pipeline: BotPipeline;
  let anna: { id: number; name: string; color: string };
  let oleg: { id: number };

  beforeEach(async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(NOW);
    ai = new ScriptedAi();
    t = await createTestApp({ ai });
    pipeline = new BotPipeline(t.ctx, 0);
    handleStaffCommand(t.ctx, STAFF, issueStaffCode(t.ctx.db).code);
    anna = await make(t, '/api/employees', { name: 'Анна', login: 'anna', password: 'secret123', phone: '+7 999 000-11-22', isMaster: true });
    oleg = await make(t, '/api/employees', { name: 'Олег', login: 'oleg', password: 'secret123', phone: '+79990003344', isMaster: true });
    await t.api('PATCH', `/api/employees/${oleg.id}`, { active: false });
  });
  afterEach(async () => {
    await t.close();
    vi.useRealTimers();
  });

  const chat = async (chatId = CHAT) => (await t.api('GET', '/api/bot/chats')).json().items.find((c: { chatId: number }) => c.chatId === chatId);
  const share = (phone: string, userId = CHAT, who = from) =>
    handleContact(t.ctx, { ...who, userId: who.chatId }, { userId, phone, firstName: who.telegramName ?? 'X', lastName: undefined });
  const toolNames = (call: number) => (ai.calls[call]!.tools ?? []).map((tool) => (tool as Anthropic.Tool).name);
  const toolResults = (call: number) => (ai.calls[call]!.messages.at(-1)!.content as Anthropic.ToolResultBlockParam[]).map((r) => ({ content: String(r.content), isError: r.is_error }));

  it('recognises only the sender’s own contact with an active employee’s phone', async () => {
    // A forwarded contact card (someone else's user_id) is refused.
    const forwarded = await share('89990001122', 12345);
    expect(forwarded.text).toMatch(/своим номером/);
    expect((await chat()).employee).toBeNull();

    // A deactivated employee's phone is just a client.
    const olegChat = { chatId: CHAT + 1, telegramName: 'Олег', username: null };
    const asClient = await share('+79990003344', olegChat.chatId, olegChat);
    expect(asClient).toMatchObject({ text: 'Спасибо, Олег! Номер сохранён ✅ Чем могу помочь?', linked: true });
    expect((await chat(olegChat.chatId)).employee).toBeNull();

    const staff = await share('8 (999) 000-11-22');
    expect(staff).toMatchObject({ staff: true, linked: false });
    expect(staff.text).toMatch(/^Здравствуйте, Анна! Узнал вас — вы сотрудник MIKAN STUDIO ✅/);
    expect((await chat()).employee).toEqual({ id: anna.id, name: 'Анна', color: anna.color });
    expect((await t.api('GET', '/api/clients?search=0001122')).json().items).toHaveLength(0); // no client card created
    expect(t.gateway.textsTo(STAFF).at(-1)).toBe('🔑 Анна подключил(а) Telegram к боту как сотрудник (@anna_m)');
    expect(getStaffChatId(t.ctx.db)).toBe(STAFF); // the /staff notification chat is untouched
    expect(handleStart(t.ctx, from, '')).toMatchObject({ staff: true, text: expect.stringMatching(/^Здравствуйте, Анна!/) });

    // The app unlinks the employee; unknown chats → 404.
    const unlinked = await t.api('DELETE', `/api/bot/chats/${CHAT}/employee`);
    expect(unlinked.statusCode).toBe(204);
    expect((await chat()).employee).toBeNull();
    expect((await t.api('DELETE', '/api/bot/chats/1/employee')).statusCode).toBe(404);
    expect(handleStart(t.ctx, from, '').staff).toBeUndefined();
  });

  it('answers staff with the staff prompt and tools; data of every master, money and quantities included', async () => {
    await share('+79990001122');
    const client = await make(t, '/api/clients', { name: 'Иван', lastName: 'Петров', phone: '+79991234567', notes: 'Аллергия на никель' });
    const helix = await make(t, '/api/services', { name: 'Хеликс', category: 'piercing', price: 3000, durationMin: 30 });
    const today = await make(t, '/api/appointments', {
      clientId: client.id, masterId: 1, services: [{ serviceId: helix.id }], startsAt: '2026-10-15T12:00:00Z', depositRequired: 1000, notes: 'Принести эскиз',
    });
    await make(t, '/api/appointments', { clientId: client.id, masterId: anna.id, startsAt: '2026-10-16T12:00:00Z', endsAt: '2026-10-16T13:00:00Z', title: 'Консультация' });
    await make(t, '/api/products', { kind: 'jewelry', name: 'Лабрет', price: 1500, variants: [{ name: '6 мм', initialQuantity: 7, minQuantity: 1 }, { name: '8 мм', initialQuantity: 1, minQuantity: 2 }] });
    await make(t, '/api/sales', { clientId: client.id, items: [{ type: 'service', name: 'Хеликс', quantity: 1, price: 3000 }], discount: 0, payments: { cash: 3000, card: 0, transfer: 0 } });

    ai.push(
      message([
        toolUse('a', 'today', {}),
        toolUse('b', 'appointments', { from: '2026-10-15', to: '2026-10-16' }),
        toolUse('c', 'client_info', { query: 'Петров' }),
        toolUse('d', 'analytics', { from: '2026-10-01', to: '2026-10-31' }),
        toolUse('e', 'stock', { query: 'лабрет' }),
        toolUse('f', 'stock', { lowOnly: true }),
      ], 'tool_use'),
      message([text('Сегодня одна запись, выручка 3 000 ₽.')]),
    );
    pipeline.receive(from, 'Что у нас сегодня?');
    await pipeline.idle();

    expect(toolNames(0)).toEqual(STAFF_TOOL_NAMES);
    const system = ai.calls[0]!.system as Anthropic.TextBlockParam[];
    expect(system[0]!.text).toContain('С тобой пишет сотрудник студии');
    expect(system[1]!.text).toContain(`Сотрудник: Анна (мастер) [id ${anna.id}].`);
    const [day, list, card, report, stock, low] = toolResults(1);
    expect(day!.content).toContain(`№${today.id} · чт 15.10 15:00–15:30 · Иван Петров (+79991234567) · мастер Админ · Хеликс 3 000 ₽ · итого 3 000 ₽ · ожидает подтверждения · предоплата 0 ₽ из 1 000 ₽ (ждём) · заметка: Принести эскиз`);
    expect(day!.content).toContain('Продажи сегодня: 1 на 3 000 ₽ (наличные 3 000 ₽');
    expect(list!.content).toContain('Всего записей: 2');
    expect(list!.content).toContain('мастер Анна · Консультация');
    expect(card!.content).toContain('Клиент [id');
    expect(card!.content).toContain('Заметки: Аллергия на никель');
    expect(card!.content).toContain('Покупок на 3 000 ₽');
    expect(JSON.parse(report!.content.slice(report!.content.indexOf('{')))).toMatchObject({ revenue: 3000, salesCount: 1, payments: { cash: 3000 } });
    expect(stock!.content).toContain('Лабрет (украшение) · 6 мм: 7 шт, 8 мм: 1 шт ⚠️ мин. 2 · цена 1 500 ₽');
    expect(low!.content).toContain('Лабрет');
    expect(t.gateway.textsTo(CHAT).at(-1)).toBe('Сегодня одна запись, выручка 3 000 ₽.');
    expect((await chat()).needsAttention).toBe(false);
  });

  it('never gives client chats the staff tools, and a deactivated employee loses staff mode at once', async () => {
    const client = { chatId: CHAT + 2, telegramName: 'Мария', username: null };
    ai.push(message([toolUse('x', 'analytics', { from: '2026-10-01', to: '2026-10-31' }), toolUse('y', 'stock', {})], 'tool_use'), message([text('Не могу подсказать.')]));
    pipeline.receive(client, 'Какая у вас выручка за месяц?');
    await pipeline.idle();
    expect(toolNames(0).some((name) => STAFF_TOOL_NAMES.includes(name))).toBe(false);
    expect(toolResults(1)).toEqual([
      { content: 'Неизвестный инструмент analytics', isError: true },
      { content: 'Неизвестный инструмент stock', isError: true },
    ]);
    expect(STAFF_TOOLS.map((tool) => tool.name)).toEqual(STAFF_TOOL_NAMES);

    await share('+79990001122');
    await t.api('PATCH', `/api/employees/${anna.id}`, { active: false });
    expect((await chat()).employee).toBeNull();
    ai.push(message([text('Здравствуйте! Чем могу помочь?')]));
    pipeline.receive(from, 'Сколько выручки сегодня?');
    await pipeline.idle();
    expect(toolNames(2)).not.toContain('analytics');
    expect((ai.calls[2]!.system as Anthropic.TextBlockParam[])[0]!.text).not.toContain('С тобой пишет сотрудник студии');

    // Staff chats are not escalated when the AI is unavailable.
    await t.api('PATCH', `/api/employees/${anna.id}`, { active: true });
    await t.api('PUT', '/api/settings/bot', { aiEnabled: false });
    pipeline.receive(from, 'Записи на завтра?');
    await pipeline.idle();
    expect(t.gateway.textsTo(CHAT).at(-1)).toBe(REPLIES.staffUnavailable);
    expect((await chat()).needsAttention).toBe(false);
  });
});
