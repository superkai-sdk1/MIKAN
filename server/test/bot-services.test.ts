import fs from 'node:fs';
import path from 'node:path';
import type Anthropic from '@anthropic-ai/sdk';
import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { BotPipeline } from '../src/bot/pipeline.js';
import { buildClientContext, buildStablePrompt } from '../src/bot/prompt.js';
import { appointments, appointmentServices, clients, employees } from '../src/db/schema.js';
import { upsertChat } from '../src/domain/bot-chats.js';
import { DAY_MS } from '../src/lib/time.js';
import { createTestApp, make, message, ScriptedAi, text, toolUse, type TestApp } from './helpers.js';

const CHAT = 700_002;
const from = { chatId: CHAT, telegramName: 'Мария', username: 'masha' };
const PNG = Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), Buffer.alloc(16)]);
const NIPPLE_CAPTION = '**Соски**\nот 2 500 до 4 000 ₽\nВарианты:\n• Один — 2 500 ₽\n• Два — 4 000 ₽\nПрокол через сосок';

describe('bot: services price list and show_service', () => {
  let t: TestApp;
  let ai: ScriptedAi;
  let pipeline: BotPipeline;

  beforeEach(async () => {
    ai = new ScriptedAi();
    t = await createTestApp({ ai });
    pipeline = new BotPipeline(t.ctx, 0);
  });
  afterEach(async () => {
    await t.close();
  });

  const upload = (name: string) => {
    const file = path.join(t.ctx.config.dataDir, 'uploads', name);
    fs.writeFileSync(file, PNG);
    return file;
  };
  const say = async (msg: string) => {
    pipeline.receive(from, msg);
    await pipeline.idle();
  };
  /** Tool results the model received in the given AI call. */
  const toolResults = (call: number) => {
    const messages = ai.calls[call]!.messages;
    return messages[messages.length - 1]!.content as Anthropic.ToolResultBlockParam[];
  };
  const nipple = () =>
    make(t, '/api/services', {
      name: 'Соски', category: 'piercing', group: 'Тело', price: 2500, priceMax: 4000, durationMin: 45, sort: 2,
      description: 'Прокол через сосок', imageUrl: '/uploads/nipple.png',
      variants: [{ name: 'Один', price: 2500 }, { name: 'Два', price: 4000, durationMin: 60 }],
    });

  it('lists active services by category and group with ids, prices, variants and picture marks', async () => {
    const lobe = await make(t, '/api/services', { name: 'Мочка', category: 'piercing', group: 'Ухо', price: 2500, durationMin: 30, sort: 1 });
    const n = await nipple();
    const jewelry = await make(t, '/api/services', { name: 'Подбор украшения', category: 'piercing', price: 0, durationMin: 10, sort: 3 });
    const mini = await make(t, '/api/services', { name: 'Тату мини', category: 'tattoo', price: 5000, priceFrom: true, durationMin: 60, photos: ['/uploads/w.jpg'] });
    const big = await make(t, '/api/services', { name: 'Тату большое', category: 'tattoo', group: 'Крупные', price: 0, priceMax: 10000, durationMin: 240 });
    const consult = await make(t, '/api/services', { name: 'Консультация', category: 'other', price: 0, durationMin: 15 });
    await make(t, '/api/services', { name: 'Скрытая', category: 'piercing', price: 1, durationMin: 10, active: false });

    const prompt = buildStablePrompt(t.ctx.db);
    expect(prompt).toContain(
      [
        '## Услуги и цены',
        '### Тату',
        `• [id ${mini.id}] Тату мини · от 5 000 ₽ · около 60 мин · есть картинка`,
        'Крупные:',
        `• [id ${big.id}] Тату большое · до 10 000 ₽ · около 240 мин`,
        '',
        '### Пирсинг',
        `• [id ${jewelry.id}] Подбор украшения · Бесплатно · около 10 мин`,
        'Ухо:',
        `• [id ${lobe.id}] Мочка · 2 500 ₽ · около 30 мин`,
        'Тело:',
        `• [id ${n.id}] Соски · от 2 500 до 4 000 ₽ · около 45 мин · варианты: Один — 2 500 ₽; Два — 4 000 ₽ (60 мин) · есть картинка · Прокол через сосок`,
        '',
        '### Другое',
        `• [id ${consult.id}] Консультация · Бесплатно · около 15 мин`,
      ].join('\n'),
    );
    expect(prompt).not.toContain('Скрытая');
    expect(prompt).toContain('вызови show_service');
  });

  it('sends the service picture after the text reply, once per conversation', async () => {
    const file = upload('nipple.png');
    const n = await nipple();
    ai.push(message([toolUse('s1', 'show_service', { serviceId: n.id })], 'tool_use'), message([text('Прокол сосков — от 2 500 ₽.')]));
    await say('Сколько стоит прокол сосков?');

    expect(String(toolResults(1)[0]!.content)).toContain('Картинка услуги «Соски» с ценой и вариантами будет отправлена');
    expect(t.gateway.textsTo(CHAT)).toEqual(['Прокол сосков — от 2 500 ₽.']);
    expect(t.gateway.photos).toEqual([{ chatId: CHAT, photo: { kind: 'file', path: file }, caption: NIPPLE_CAPTION }]);
    const history = async () => (await t.api('GET', `/api/bot/chats/${CHAT}/messages`)).json().items.map((m: { text: string }) => m.text);
    expect(await history()).toEqual(['Сколько стоит прокол сосков?', 'Прокол сосков — от 2 500 ₽.', `[Фото] ${NIPPLE_CAPTION}`]);

    ai.push(
      message([toolUse('s2', 'show_service', { serviceId: n.id }), toolUse('s3', 'show_service', { serviceId: n.id })], 'tool_use'),
      message([text('Два прокола — 4 000 ₽.')]),
    );
    await say('А сколько за два?');
    const repeated = toolResults(3);
    expect(repeated.map((r) => r.is_error)).toEqual([false, false]);
    expect(repeated.every((r) => String(r.content).includes('уже отправлена клиенту в этом диалоге'))).toBe(true);
    expect(t.gateway.photos).toHaveLength(1);
    expect(t.gateway.textsTo(CHAT)).toEqual(['Прокол сосков — от 2 500 ₽.', 'Два прокола — 4 000 ₽.']);
  });

  it('rejects unknown, inactive and malformed ids; answers in text when there is no picture', async () => {
    upload('hidden.png');
    const hidden = await make(t, '/api/services', { name: 'Скрытая', category: 'piercing', price: 1, durationMin: 10, active: false, imageUrl: '/uploads/hidden.png' });
    const plain = await make(t, '/api/services', { name: 'Мочка', category: 'piercing', price: 2500, durationMin: 30, imageUrl: '/uploads/missing.png' });
    ai.push(
      message([
        toolUse('a', 'show_service', { serviceId: 999 }),
        toolUse('b', 'show_service', { serviceId: hidden.id }),
        toolUse('c', 'show_service', { serviceId: 'one' }),
        toolUse('d', 'show_service', { serviceId: plain.id }),
      ], 'tool_use'),
      message([text('Прокол мочки — 2 500 ₽.')]),
    );
    await say('Покажите мочку');
    const results = toolResults(1);
    expect(results.map((r) => r.is_error)).toEqual([true, true, true, false]);
    expect(String(results[0]!.content)).toBe('Такой услуги нет в прайсе. Возьми id из раздела «Услуги и цены».');
    expect(String(results[2]!.content)).toContain('нужен id услуги');
    expect(String(results[3]!.content)).toBe('У услуги «Мочка» нет картинки — просто ответь клиенту текстом.');
    expect(t.gateway.photos).toEqual([]);
    expect(t.gateway.textsTo(CHAT)).toEqual(['Прокол мочки — 2 500 ₽.']);
  });

  it('uses the first photo of works when the cover cannot be sent, and the caption when Telegram fails', async () => {
    const work = upload('work.jpg');
    const s = await make(t, '/api/services', {
      name: 'Тату мини', category: 'tattoo', price: 5000, priceFrom: true, durationMin: 60,
      imageUrl: '/uploads/cover.heic', photos: ['/uploads/work.jpg', 'https://cdn.test/2.jpg'],
    });
    ai.push(message([toolUse('s', 'show_service', { serviceId: s.id })], 'tool_use'), message([text('Мини-тату — от 5 000 ₽.')]));
    await say('Что по мини тату?');
    expect(t.gateway.photos).toEqual([{ chatId: CHAT, photo: { kind: 'file', path: work }, caption: '**Тату мини**\nот 5 000 ₽' }]);

    const other = await make(t, '/api/services', { name: 'Брови', category: 'other', price: 0, durationMin: 30, imageUrl: 'https://cdn.test/brows.png' });
    t.gateway.sendPhoto = async () => {
      throw new Error('Telegram: wrong file identifier');
    };
    ai.push(message([toolUse('o', 'show_service', { serviceId: other.id })], 'tool_use'), message([text('Брови — бесплатно.')]));
    await say('А брови?');
    expect(t.gateway.textsTo(CHAT)).toEqual(['Мини-тату — от 5 000 ₽.', 'Брови — бесплатно.', '**Брови**\nБесплатно']);
  });

  it('only notes the picture in /bot/test', async () => {
    upload('nipple.png');
    const n = await nipple();
    ai.push(message([toolUse('s', 'show_service', { serviceId: n.id })], 'tool_use'), message([text('Вот прокол сосков.')]));
    const res = await t.api('POST', '/api/bot/test', { text: 'Расскажите про соски' });
    expect(res.json().reply).toBe('Вот прокол сосков.\n\n— Тест: показана бы картинка услуги: Соски');
    expect(t.gateway.photos).toEqual([]);
  });

  it("names the client's appointments by their service lines", async () => {
    const lobe = await make(t, '/api/services', { name: 'Мочка', category: 'piercing', price: 2500, durationMin: 30 });
    const client = await make(t, '/api/clients', { name: 'Мария', phone: '+79991112233' });
    upsertChat(t.ctx.db, CHAT, { clientId: client.id });
    const master = t.ctx.db.select().from(employees).get()!;
    const now = Date.now();
    const insert = (startsAt: number, status: string, extra: { serviceId?: number; title?: string } = {}) =>
      t.ctx.db
        .insert(appointments)
        .values({ clientId: client.id, masterId: master.id, startsAt, endsAt: startsAt + 3_600_000, status, createdAt: now, updatedAt: now, ...extra })
        .returning()
        .get();
    const withLines = insert(now + DAY_MS, 'scheduled', { serviceId: lobe.id, title: 'не показывать' });
    t.ctx.db
      .insert(appointmentServices)
      .values([
        { appointmentId: withLines.id, serviceId: null, name: 'Подбор украшения', price: 0, position: 1 },
        { appointmentId: withLines.id, serviceId: lobe.id, name: 'Мочка — Две', price: 4000, position: 0 },
      ])
      .run();
    insert(now + 2 * DAY_MS, 'confirmed', { title: 'Эскиз на предплечье' });
    insert(now - 3 * DAY_MS, 'completed', { serviceId: lobe.id });
    insert(now - 4 * DAY_MS, 'completed');

    const row = t.ctx.db.select().from(clients).where(eq(clients.id, client.id)).get()!;
    const context = buildClientContext(t.ctx.db, now, row, null);
    expect(context).toMatch(/Ближайшие записи:\n• .+ — Мочка — Две, Подбор украшения, мастер /);
    expect(context).toMatch(/\n• .+ — Эскиз на предплечье, мастер /);
    expect(context).not.toContain('не показывать');
    expect(context).toMatch(/Недавние процедуры:\n• .+ — Мочка \(прошло дней: 3\)\n• .+ — процедура \(прошло дней: 4\)/);
  });
});

describe('bot tone', () => {
  let t: TestApp;
  beforeEach(async () => {
    t = await createTestApp();
  });
  afterEach(async () => {
    await t.close();
  });

  it('tells the bot to write simply and in a friendly way, with examples, and without office jargon', () => {
    const prompt = buildStablePrompt(t.ctx.db);
    expect(prompt).toMatch(/^Ты — администратор тату- и пирсинг-студии «MIKAN STUDIO» в Telegram\. Пишешь клиентам как живой человек из студии: просто, тепло и по-дружески, на «вы»\./);
    expect(prompt).toContain('Коротко: 1–3 простых предложения. Одно сообщение — одна мысль и не больше одного вопроса.');
    expect(prompt).toContain('не пиши «в системе», «в данных», «в прайсе не указано»');
    expect(prompt).toContain('Хорошо: «Хороший вопрос! Уточню у администратора — он ответит прямо здесь 🙂»');
    // Facts-only stays the first rule.
    expect(prompt).toContain('1. Говори только то, что есть в «Данных студии» и в ответах инструментов.');
  });
});
