import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createTestApp, make, type TestApp } from './helpers.js';

describe('products & stock', () => {
  let t: TestApp;
  beforeEach(async () => {
    t = await createTestApp();
  });
  afterEach(async () => {
    await t.close();
  });

  const labret = {
    kind: 'jewelry',
    name: 'Лабрет',
    sku: 'LB-12-08',
    category: 'Лабрет',
    material: 'Титан G23',
    size: '1.2×8 мм',
    price: 1500,
    cost: 600,
    minQuantity: 3,
    initialQuantity: 12,
  };

  it('creates a product with initialQuantity as a receipt movement', async () => {
    const p = await make(t, '/api/products', labret);
    const { initialQuantity: _initial, ...fields } = labret;
    expect(p).not.toHaveProperty('initialQuantity');
    expect(p).toMatchObject({ ...fields, quantity: 12, unit: 'шт', active: true, lowStock: false, photoUrl: null });
    const moves = await t.api('GET', `/api/products/${p.id}/movements`);
    expect(moves.json().total).toBe(1);
    expect(moves.json().items[0]).toMatchObject({
      productId: p.id,
      productName: 'Лабрет',
      delta: 12,
      quantityAfter: 12,
      type: 'receipt',
      note: 'Начальный остаток',
      saleId: null,
      appointmentId: null,
      employee: { id: 1, name: 'Админ', color: '#FF7A1A' },
    });
  });

  it('records receipt, writeoff, usage and adjustment movements; blocks negative stock', async () => {
    const p = await make(t, '/api/products', labret);
    const move = (body: object) => t.api('POST', `/api/products/${p.id}/movements`, body);

    const receipt = await move({ type: 'receipt', quantity: 5, note: 'Поставка' });
    expect(receipt.json().product.quantity).toBe(17);
    expect(receipt.json().movement).toMatchObject({ delta: 5, quantityAfter: 17, type: 'receipt', note: 'Поставка' });
    expect((await move({ type: 'writeoff', quantity: 2 })).json().product.quantity).toBe(15);
    expect((await move({ type: 'usage', quantity: 1 })).json().product.quantity).toBe(14);

    const adjust = await move({ type: 'adjustment', quantity: 9 });
    expect(adjust.json().movement).toMatchObject({ delta: -5, quantityAfter: 9, type: 'adjustment' });

    const tooMuch = await move({ type: 'writeoff', quantity: 10 });
    expect(tooMuch.statusCode).toBe(409);
    expect(tooMuch.json().error).toEqual({ code: 'insufficient_stock', message: 'Недостаточно на складе: Лабрет (осталось 9)' });
    expect((await t.api('GET', `/api/products/${p.id}`)).json().quantity).toBe(9);

    expect((await move({ type: 'receipt', quantity: 0 })).statusCode).toBe(400);
    expect((await move({ type: 'sale', quantity: 1 })).statusCode).toBe(400);
    expect((await move({ type: 'adjustment', quantity: 0 })).json().product).toMatchObject({ quantity: 0, lowStock: true });

    const page = await t.api('GET', `/api/products/${p.id}/movements?limit=2`);
    expect(page.json().total).toBe(6);
    expect(page.json().items.map((m: { type: string }) => m.type)).toEqual(['adjustment', 'adjustment']);

    const global = await t.api('GET', '/api/stock/movements?type=writeoff');
    expect(global.json().total).toBe(1);
    expect((await t.api('GET', '/api/stock/movements')).json().total).toBe(6);
  });

  it('lists with filters, sorted by category then name; PATCH never changes quantity', async () => {
    const ring = await make(t, '/api/products', { kind: 'jewelry', name: 'Кольцо', category: 'Кольца', price: 2000, initialQuantity: 1, minQuantity: 2 });
    await make(t, '/api/products', labret);
    await make(t, '/api/products', { kind: 'consumable', name: 'Игла 1.2', price: 0, initialQuantity: 100, minQuantity: 20, unit: 'шт' });
    const hidden = await make(t, '/api/products', { kind: 'jewelry', name: 'Старый', price: 100, active: false });

    const names = async (q: string) => (await t.api('GET', `/api/products${q}`)).json().items.map((p: { name: string }) => p.name);
    expect(await names('')).toEqual(['Игла 1.2', 'Кольцо', 'Лабрет']);
    expect(await names('?kind=jewelry')).toEqual(['Кольцо', 'Лабрет']);
    expect(await names('?lowStock=true')).toEqual(['Кольцо']);
    expect(await names('?search=титан')).toEqual(['Лабрет']);
    expect(await names('?includeInactive=true')).toContain('Старый');

    const patched = await t.api('PATCH', `/api/products/${ring.id}`, { quantity: 999, price: 2500, material: 'Золото', sku: null });
    expect(patched.json()).toMatchObject({ quantity: 1, price: 2500, material: 'Золото', sku: null });
    expect((await t.api('PATCH', `/api/products/${hidden.id}`, { photoUrl: 'ftp://x' })).statusCode).toBe(400);
    expect((await t.api('GET', '/api/products/999')).statusCode).toBe(404);
    expect((await t.api('GET', '/api/products/999/movements')).statusCode).toBe(404);
  });
});
