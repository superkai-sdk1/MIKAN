import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { productVariants } from '../src/db/schema.js';
import { createTestApp, make, type TestApp } from './helpers.js';

interface Size {
  id: number;
  name: string;
  quantity: number;
}

describe('jewelry sizes: catalog and stock', () => {
  let t: TestApp;
  beforeEach(async () => {
    t = await createTestApp();
  });
  afterEach(async () => {
    await t.close();
  });

  const labret = (overrides: object = {}) => ({
    kind: 'jewelry',
    name: 'Лабрет',
    sku: 'LB-12',
    category: 'Лабрет',
    material: 'Титан ASTM F136',
    threadType: 'internal',
    thicknessMm: 1.2,
    color: 'Серебристый',
    stone: 'Фианит',
    supplier: 'Industrial Strength',
    price: 1500,
    cost: 600,
    photos: ['/uploads/a.jpg', '/uploads/b.jpg'],
    variants: [
      { name: '6 мм', minQuantity: 1, initialQuantity: 4 },
      { name: '8 мм', sku: 'LB-12-08', price: 1700, cost: 700, minQuantity: 1, initialQuantity: 0 },
      { name: '10 мм', minQuantity: 0, initialQuantity: 2 },
    ],
    ...overrides,
  });
  const sizes = (p: { variants: Size[] }) => p.variants.map((v) => [v.name, v.quantity]);
  const sizeId = (p: { variants: Size[] }, name: string) => p.variants.find((v) => v.name === name)!.id;
  const get = async (id: number) => (await t.api('GET', `/api/products/${id}`)).json();

  it('creates a product with sizes, attributes, photos and linked services', async () => {
    const helix = await make(t, '/api/services', { name: 'Хеликс', category: 'piercing', price: 3000, durationMin: 30 });
    const p = await make(t, '/api/products', labret({ serviceIds: [helix.id, helix.id] }));
    expect(p).toMatchObject({
      material: 'Титан ASTM F136',
      threadType: 'internal',
      thicknessMm: 1.2,
      color: 'Серебристый',
      stone: 'Фианит',
      supplier: 'Industrial Strength',
      photos: ['/uploads/a.jpg', '/uploads/b.jpg'],
      photoUrl: '/uploads/a.jpg',
      serviceIds: [helix.id],
      quantity: 6,
      minQuantity: 2,
      lowStock: true,
      size: '6 мм, 8 мм, 10 мм',
    });
    expect(p.variants).toEqual([
      { id: expect.any(Number), name: '6 мм', sku: null, price: null, cost: null, quantity: 4, minQuantity: 1, lowStock: false },
      { id: expect.any(Number), name: '8 мм', sku: 'LB-12-08', price: 1700, cost: 700, quantity: 0, minQuantity: 1, lowStock: true },
      { id: expect.any(Number), name: '10 мм', sku: null, price: null, cost: null, quantity: 2, minQuantity: 0, lowStock: false },
    ]);
    const moves = (await t.api('GET', `/api/products/${p.id}/movements`)).json().items;
    expect(moves.map((m: { variantName: string; delta: number; type: string }) => [m.variantName, m.delta, m.type])).toEqual([
      ['10 мм', 2, 'receipt'],
      ['6 мм', 4, 'receipt'],
    ]);
  });

  it('validates sizes, attributes and services', async () => {
    const error = async (body: object) => (await t.api('POST', '/api/products', body)).json().error.message;
    expect(await error(labret({ variants: [{ name: '8 мм' }, { name: ' 8 ММ ' }] }))).toBe('Размер «8 ММ» указан дважды');
    expect(await error(labret({ variants: [{ name: '6 мм' }, { name: '' }] }))).toBe('Размер №2: укажите название размера');
    expect(await error(labret({ variants: [] }))).toBe('«Варианты»: нужно указать хотя бы 1');
    expect(await error({ kind: 'consumable', name: 'Иглы', variants: [{ name: '1.2' }, { name: '1.6' }] })).toBe(
      'У расходника не может быть нескольких размеров — заведите отдельные позиции',
    );
    expect(await error(labret({ serviceIds: [999] }))).toBe('Услуга не найдена');
    expect(await error(labret({ thicknessMm: 1.234 }))).toBe('«Толщина»: не больше двух знаков после запятой');
    expect(await error(labret({ threadType: 'magnetic' }))).toContain('«Резьба»: недопустимое значение');
    expect(await error(labret({ photos: ['ftp://x'] }))).toBe('«Фото (№1)»: ссылка на фото должна начинаться с /uploads/ или http(s)://');
    expect(await error(labret({ variants: [{ id: 5, name: '6 мм' }] }))).toBe('Размер №1 не найден');
  });

  it('PATCH replaces the sizes: renames, reorders, adds with initial stock, deletes or archives removed ones', async () => {
    const p = await make(t, '/api/products', labret());
    const [six, eight, ten] = p.variants as Size[];
    // Sell nothing yet: 8 мм has no history, 10 мм has a receipt.
    await t.api('POST', `/api/products/${p.id}/movements`, { type: 'writeoff', variantId: ten!.id, quantity: 2 });

    const patched = await t.api('PATCH', `/api/products/${p.id}`, {
      variants: [
        { id: eight!.id, name: '8 мм', price: null },
        { id: six!.id, name: '6 мм (короткий)', minQuantity: 2 },
        { name: '12 мм', initialQuantity: 3 },
      ],
    });
    expect(patched.statusCode).toBe(200);
    expect(sizes(patched.json())).toEqual([
      ['8 мм', 0],
      ['6 мм (короткий)', 4],
      ['12 мм', 3],
    ]);
    expect(patched.json().variants[0]).toMatchObject({ sku: 'LB-12-08', price: null, cost: 700 });
    expect(patched.json().variants[1]).toMatchObject({ minQuantity: 2 });
    // 10 мм had movements: archived, still named by its history.
    const archived = t.ctx.db.select().from(productVariants).where(eq(productVariants.id, ten!.id)).get();
    expect(archived).toMatchObject({ archived: true, quantity: 0 });
    const history = (await t.api('GET', `/api/products/${p.id}/movements?variantId=${ten!.id}`)).json();
    expect(history.items.map((m: { variantName: string }) => m.variantName)).toEqual(['10 мм', '10 мм']);

    // Removing a size with stock is refused; removing one without history deletes it.
    const withStock = await t.api('PATCH', `/api/products/${p.id}`, { variants: [{ id: eight!.id }] });
    expect(withStock.statusCode).toBe(409);
    expect(withStock.json().error.message).toBe('Размер «6 мм (короткий)»: на складе 4 шт — спишите остаток, прежде чем удалять размер');
    const twelve = sizeId(patched.json(), '12 мм');
    await t.api('POST', `/api/products/${p.id}/movements/batch`, {
      type: 'writeoff',
      lines: [{ variantId: twelve, quantity: 3 }],
    });
    const fewer = await t.api('PATCH', `/api/products/${p.id}`, { variants: [{ id: six!.id }, { id: twelve }] });
    expect(sizes(fewer.json())).toEqual([
      ['6 мм (короткий)', 4],
      ['12 мм', 0],
    ]);
    expect(t.ctx.db.select().from(productVariants).where(eq(productVariants.id, eight!.id)).get()).toBeUndefined();

    const unknown = await t.api('PATCH', `/api/products/${p.id}`, { variants: [{ id: ten!.id, name: '10 мм' }] });
    expect(unknown.statusCode).toBe(400);
    expect(unknown.json().error.message).toBe('Размер №1 не найден — обновите карточку товара');
  });

  it('older builds edit the only size through size/minQuantity and get 409 when the product has several', async () => {
    const single = await make(t, '/api/products', { kind: 'jewelry', name: 'Кольцо', size: '1.2×10 мм', price: 2000, minQuantity: 1, initialQuantity: 2 });
    expect(single).toMatchObject({ size: '1.2×10 мм', quantity: 2, minQuantity: 1, variants: [{ name: '1.2×10 мм', quantity: 2 }] });
    const renamed = await t.api('PATCH', `/api/products/${single.id}`, { size: '1.2×8 мм', minQuantity: 3, name: 'Кольцо' });
    expect(renamed.json()).toMatchObject({ size: '1.2×8 мм', minQuantity: 3, lowStock: true, variants: [{ id: single.variants[0].id, name: '1.2×8 мм' }] });

    const many = await make(t, '/api/products', labret());
    // What an older build resends unchanged is accepted.
    const same = await t.api('PATCH', `/api/products/${many.id}`, { name: 'Лабрет титан', size: '6 мм, 8 мм, 10 мм', minQuantity: 2 });
    expect(same.statusCode).toBe(200);
    expect(same.json().name).toBe('Лабрет титан');
    for (const body of [{ size: '8 мм' }, { minQuantity: 5 }]) {
      const res = await t.api('PATCH', `/api/products/${many.id}`, body);
      expect(res.statusCode).toBe(409);
      expect(res.json().error.message).toBe('У «Лабрет титан» несколько размеров — обновите приложение MIKAN, чтобы изменить их');
    }
    const consumable = await t.api('PATCH', `/api/products/${many.id}`, { kind: 'consumable' });
    expect(consumable.statusCode).toBe(400);
  });

  it('older builds edit only the cover photo; photos replace the whole gallery', async () => {
    const p = await make(t, '/api/products', labret());
    const cover = await t.api('PATCH', `/api/products/${p.id}`, { photoUrl: '/uploads/c.jpg' });
    expect(cover.json()).toMatchObject({ photos: ['/uploads/c.jpg', '/uploads/b.jpg'], photoUrl: '/uploads/c.jpg' });
    const unchanged = await t.api('PATCH', `/api/products/${p.id}`, { photoUrl: '/uploads/c.jpg' });
    expect(unchanged.json().photos).toEqual(['/uploads/c.jpg', '/uploads/b.jpg']);
    const removed = await t.api('PATCH', `/api/products/${p.id}`, { photoUrl: null });
    expect(removed.json()).toMatchObject({ photos: ['/uploads/b.jpg'], photoUrl: '/uploads/b.jpg' });
    const gallery = await t.api('PATCH', `/api/products/${p.id}`, { photos: [], photoUrl: '/uploads/ignored.jpg' });
    expect(gallery.json()).toMatchObject({ photos: [], photoUrl: null });
  });

  it('records movements per size; older builds need a size only when there are several', async () => {
    const p = await make(t, '/api/products', labret());
    const six = sizeId(p, '6 мм');
    const move = (body: object) => t.api('POST', `/api/products/${p.id}/movements`, body);

    const noSize = await move({ type: 'receipt', quantity: 1 });
    expect(noSize.statusCode).toBe(409);
    expect(noSize.json().error.message).toBe('У «Лабрет» несколько размеров — обновите приложение MIKAN, чтобы провести операцию по размеру');

    const receipt = await move({ type: 'receipt', variantId: six, quantity: 3, note: 'Поставка' });
    expect(receipt.json().movement).toMatchObject({ variantId: six, variantName: '6 мм', delta: 3, quantityAfter: 7, productName: 'Лабрет' });
    expect(receipt.json().product.quantity).toBe(9);

    const tooMuch = await move({ type: 'writeoff', variantId: sizeId(p, '8 мм'), quantity: 1 });
    expect(tooMuch.json().error).toEqual({ code: 'insufficient_stock', message: 'Недостаточно на складе: Лабрет — 8 мм (осталось 0)' });

    const other = await make(t, '/api/products', { kind: 'jewelry', name: 'Кольцо', price: 900, initialQuantity: 1 });
    const foreign = await move({ type: 'receipt', variantId: other.variants[0].id, quantity: 1 });
    expect(foreign.statusCode).toBe(400);
    expect(foreign.json().error.message).toBe('Размер не найден');
    // A product without sizes keeps working without variantId.
    const plain = await t.api('POST', `/api/products/${other.id}/movements`, { type: 'adjustment', quantity: 5 });
    expect(plain.json().movement).toMatchObject({ variantName: '', delta: 4, quantityAfter: 5 });
  });

  it('records a batch over several sizes atomically and idempotently', async () => {
    const p = await make(t, '/api/products', labret());
    const [six, eight, ten] = (p.variants as Size[]).map((v) => v.id);
    const batch = (body: object, key?: string) =>
      t.app.inject({
        method: 'POST',
        url: `/api/products/${p.id}/movements/batch`,
        headers: { authorization: `Bearer ${t.token}`, ...(key ? { 'idempotency-key': key } : {}) },
        payload: body,
      });

    const key = '0f8fad5b-d9cb-469f-a165-70867728950e';
    const delivery = { type: 'receipt', note: 'Поставка', lines: [{ variantId: eight, quantity: 5 }, { variantId: six, quantity: 1 }] };
    const first = await batch(delivery, key);
    expect(first.statusCode).toBe(200);
    expect(first.json().movements.map((m: { variantName: string; quantityAfter: number }) => [m.variantName, m.quantityAfter])).toEqual([
      ['8 мм', 5],
      ['6 мм', 5],
    ]);
    const replay = await batch(delivery, key);
    expect(replay.headers['idempotent-replayed']).toBe('true');
    expect(sizes(await get(p.id))).toEqual([
      ['6 мм', 5],
      ['8 мм', 5],
      ['10 мм', 2],
    ]);

    const count = await batch({ type: 'adjustment', lines: [{ variantId: six, quantity: 5 }, { variantId: ten, quantity: 1 }] });
    expect(count.json().movements.map((m: { variantId: number; delta: number }) => [m.variantId, m.delta])).toEqual([[ten, -1]]);
    const nothing = await batch({ type: 'adjustment', lines: [{ variantId: six, quantity: 5 }] });
    expect(nothing.json().error.message).toBe('Остатки не изменились');
    const twice = await batch({ type: 'receipt', lines: [{ variantId: six, quantity: 1 }, { variantId: six, quantity: 2 }] });
    expect(twice.json().error.message).toBe('Размер указан дважды');

    // One line short of stock rolls the whole batch back.
    const short = await batch({ type: 'writeoff', lines: [{ variantId: six, quantity: 1 }, { variantId: ten, quantity: 2 }] });
    expect(short.statusCode).toBe(409);
    expect(short.json().error.message).toBe('Недостаточно на складе: Лабрет — 10 мм (осталось 1)');
    expect(sizes(await get(p.id))).toEqual([
      ['6 мм', 5],
      ['8 мм', 5],
      ['10 мм', 1],
    ]);
  });

  it('lists by size: search matches size names and SKUs, lowStock means some size is low, badge counts such products', async () => {
    await make(t, '/api/products', labret());
    await make(t, '/api/products', { kind: 'jewelry', name: 'Кольцо', price: 900, minQuantity: 1, initialQuantity: 5, variants: [{ name: '8 мм', initialQuantity: 5, minQuantity: 1 }] });
    await make(t, '/api/products', { kind: 'jewelry', name: 'Банан', price: 900, stone: 'Опал', initialQuantity: 5 });
    const names = async (q: string) => (await t.api('GET', `/api/products${q}`)).json().items.map((p: { name: string }) => p.name);
    expect(await names('?search=10%20мм')).toEqual(['Лабрет']);
    expect(await names('?search=lb-12-08')).toEqual(['Лабрет']);
    expect(await names('?search=8%20мм')).toEqual(['Кольцо', 'Лабрет']);
    expect(await names('?search=опал')).toEqual(['Банан']);
    expect(await names('?lowStock=true')).toEqual(['Лабрет']);
    expect((await t.api('GET', '/api/badges')).json().lowStock).toBe(1);
  });
});
