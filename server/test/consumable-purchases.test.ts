import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createTestApp, make, type TestApp } from './helpers.js';

type Json = Record<string, any>;

describe('purchases of presence consumables', () => {
  let t: TestApp;
  let gloves: Json;

  beforeEach(async () => {
    t = await createTestApp();
    gloves = await make(t, '/api/products', { kind: 'consumable', name: 'Перчатки', stockMode: 'presence', presenceStatus: 'low', cost: 10 });
  });
  afterEach(async () => {
    await t.close();
  });

  const buy = (id: number, body: object, headers: Record<string, string> = {}) =>
    t.app.inject({ method: 'POST', url: `/api/products/${id}/purchases`, payload: body, headers: { authorization: `Bearer ${t.token}`, ...headers } });

  it('records what a restock cost and marks the consumable as in stock', async () => {
    const res = await buy(gloves.id, { amount: 3500, note: 'Перчатки, 10 упаковок' });
    expect(res.statusCode).toBe(200);
    const { product, movement } = res.json();
    expect(product).toMatchObject({ id: gloves.id, presenceStatus: 'ok', lowStock: false, quantity: 0 });
    expect(movement).toMatchObject({
      productId: gloves.id, productName: 'Перчатки', type: 'purchase', delta: 0, quantityAfter: 0, amount: 3500,
      note: 'Перчатки, 10 упаковок', employee: { id: 1 },
    });

    const low = (await buy(gloves.id, { amount: 1500, presenceStatus: 'low' })).json();
    expect(low.product.presenceStatus).toBe('low');

    const history = (await t.api('GET', `/api/products/${gloves.id}/movements`)).json();
    expect(history.items.map((m: Json) => [m.type, m.amount])).toEqual([['purchase', 1500], ['purchase', 3500]]);
    expect((await t.api('GET', '/api/stock/movements?type=purchase')).json().total).toBe(2);
    // Other movements of a presence consumable are still refused.
    expect((await t.api('POST', `/api/products/${gloves.id}/movements`, { type: 'receipt', quantity: 5 })).statusCode).toBe(400);
  });

  it('only presence consumables take purchases, for a positive amount', async () => {
    const needles = await make(t, '/api/products', { kind: 'consumable', name: 'Иглы', initialQuantity: 10 });
    const counted = await buy(needles.id, { amount: 500 });
    expect(counted.statusCode).toBe(400);
    expect(counted.json().error.message).toBe('Сумму покупки записывают для расходников «есть / нет». Для остальных — приход количеством.');
    expect((await buy(gloves.id, { amount: 0 })).statusCode).toBe(400);
    expect((await buy(gloves.id, {})).statusCode).toBe(400);
    expect((await buy(999, { amount: 100 })).statusCode).toBe(404);
  });

  it('a retried purchase with the same key is recorded once', async () => {
    const key = { 'idempotency-key': '0f8fad5b-d9cb-469f-a165-70867728950e' };
    await buy(gloves.id, { amount: 2000 }, key);
    const replay = await buy(gloves.id, { amount: 2000 }, key);
    expect(replay.headers['idempotent-replayed']).toBe('true');
    expect((await t.api('GET', `/api/products/${gloves.id}/movements`)).json().total).toBe(1);
  });

  it('the analytics counts purchases as stock expenses of their day', async () => {
    const needles = await make(t, '/api/products', { kind: 'consumable', name: 'Иглы', cost: 50, initialQuantity: 10 });
    await t.api('POST', `/api/products/${needles.id}/movements`, { type: 'usage', quantity: 2 });
    await buy(gloves.id, { amount: 3500 });
    await buy(gloves.id, { amount: 1500 });
    const from = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);
    const to = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
    const stock = (await t.api('GET', `/api/reports/analytics?from=${from}&to=${to}`)).json().stock;
    expect(stock).toMatchObject({
      usage: { quantity: 2, value: 100 },
      purchases: { count: 2, value: 5000 },
      expenses: 5100,
    });
    expect(stock.top[0]).toEqual({ productId: gloves.id, name: 'Перчатки', kind: 'consumable', type: 'purchase', quantity: 2, value: 5000 });
  });
});
