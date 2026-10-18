import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { BotPipeline } from '../src/bot/pipeline.js';
import { buildStablePrompt } from '../src/bot/prompt.js';
import { createTestApp, make, message, ScriptedAi, text, toolUse, type TestApp } from './helpers.js';

const CHAT = 700_003;
const from = { chatId: CHAT, telegramName: 'Мария', username: 'masha' };

describe('bot: jewelry sizes in stock, never quantities', () => {
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

  const jewelrySection = () => {
    const prompt = buildStablePrompt(t.ctx.db);
    return prompt.slice(prompt.indexOf('## Украшения в наличии'), prompt.indexOf('##', prompt.indexOf('## Украшения в наличии') + 5));
  };

  it('lists sizes that have stock with their prices and attributes, and nothing about how many are left', async () => {
    const helix = await make(t, '/api/services', { name: 'Хеликс', category: 'piercing', price: 3000, durationMin: 30 });
    const labret = await make(t, '/api/products', {
      kind: 'jewelry',
      name: 'Лабрет',
      category: 'Лабрет',
      material: 'Титан ASTM F136',
      threadType: 'internal',
      thicknessMm: 1.2,
      stone: 'Фианит',
      price: 1500,
      serviceIds: [helix.id],
      variants: [
        { name: '6 мм', initialQuantity: 7 },
        { name: '8 мм', initialQuantity: 0 },
        { name: '10 мм', price: 1700, initialQuantity: 1 },
      ],
    });
    await make(t, '/api/products', {
      kind: 'jewelry',
      name: 'Кольцо',
      price: 900,
      variants: [
        { name: '8 мм', initialQuantity: 2 },
        { name: '10 мм', initialQuantity: 3 },
      ],
    });
    await make(t, '/api/products', { kind: 'jewelry', name: 'Распродано', price: 900, variants: [{ name: '6 мм' }, { name: '8 мм' }] });

    const section = jewelrySection();
    expect(section).toContain(
      `• [id ${labret.id}] Лабрет · Лабрет · Титан ASTM F136 · внутренняя резьба · 1.2 мм (16G) · Фианит · подходит для: Хеликс · ` +
        'размеры в наличии: 6 мм — 1 500 ₽, 10 мм — 1 700 ₽',
    );
    expect(section).toContain('Кольцо · размеры в наличии: 8 мм, 10 мм · 900 ₽');
    expect(section).not.toContain('Распродано');
    expect(section).not.toContain('8 мм —');
    expect(section).not.toMatch(/\b[37] шт|осталось|остаток/);
    expect(buildStablePrompt(t.ctx.db)).toContain('Количество на складе не называй никогда');
  });

  it('show_products sends the cover with the sizes in stock in the caption', async () => {
    const uploads = path.join(t.ctx.config.dataDir, 'uploads');
    fs.writeFileSync(path.join(uploads, 'labret.jpg'), Buffer.from([0xff, 0xd8, 0xff, 0xe0]));
    const labret = await make(t, '/api/products', {
      kind: 'jewelry',
      name: 'Лабрет',
      material: 'Титан ASTM F136',
      thicknessMm: 1.2,
      price: 1500,
      photos: ['/uploads/labret.jpg', '/uploads/other.jpg'],
      variants: [
        { name: '6 мм', initialQuantity: 2 },
        { name: '8 мм', initialQuantity: 0 },
        { name: '10 мм', initialQuantity: 1 },
      ],
    });
    const ring = await make(t, '/api/products', {
      kind: 'jewelry',
      name: 'Кольцо',
      price: 900,
      variants: [
        { name: '8 мм', initialQuantity: 1 },
        { name: '10 мм', price: 1100, initialQuantity: 1 },
      ],
    });
    ai.push(message([toolUse('p', 'show_products', { productIds: [labret.id, ring.id] })], 'tool_use'), message([text('Вот что есть:')]));
    pipeline.receive(from, 'Покажите лабреты');
    await pipeline.idle();

    expect(t.gateway.photos).toEqual([
      {
        chatId: CHAT,
        photo: { kind: 'file', path: path.join(uploads, 'labret.jpg') },
        caption: 'Лабрет · Титан ASTM F136 · 1.2 мм (16G) — 1 500 ₽\nРазмеры в наличии: 6 мм, 10 мм',
      },
    ]);
    expect(t.gateway.textsTo(CHAT)).toEqual(['Вот что есть:', 'Кольцо — от 900 ₽\nРазмеры в наличии: 8 мм — 900 ₽, 10 мм — 1 100 ₽']);
  });
});
