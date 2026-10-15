import { describe, expect, it } from 'vitest';
import { asc } from 'drizzle-orm';
import { openDatabase } from '../src/db/client.js';
import { products, stockMovements } from '../src/db/schema.js';
import { importProducts, type ProductImportRecord } from '../src/scripts/import-products.js';

const opts = { apply: true, source: 'yclients' };
const records: ProductImportRecord[] = [
  { kind: 'consumable', name: 'Перчатки', category: 'Основные расходники', description: 'Желаемый остаток: 300', unit: 'пар', minQuantity: 100 },
  { kind: 'consumable', name: 'Бинты эластичные', category: 'Тату', description: null, unit: 'шт', minQuantity: 3 },
  { kind: 'consumable', name: 'Бинты эластичные', category: 'Основные расходники', description: null, unit: 'шт', minQuantity: 3 },
  { kind: 'jewelry', name: 'Лабрет', category: 'Лабрет', description: null, unit: 'шт', price: 1500, cost: 600, initialQuantity: 4 },
];

describe('importProducts', () => {
  it('writes nothing in dry-run mode', () => {
    const { db } = openDatabase(':memory:');

    const summary = importProducts(db, records, { ...opts, apply: false });

    expect(summary).toMatchObject({ total: 4, created: 4, existing: 0, invalid: [] });
    expect(db.select().from(products).all()).toHaveLength(0);
  });

  it('creates products, keeps same-name items in different categories, and records initial stock as a receipt', () => {
    const { db } = openDatabase(':memory:');

    importProducts(db, records, opts);

    const rows = db.select().from(products).orderBy(asc(products.id)).all();
    expect(rows.map((r) => [r.name, r.category, r.unit, r.minQuantity, r.quantity])).toEqual([
      ['Перчатки', 'Основные расходники', 'пар', 100, 0],
      ['Бинты эластичные', 'Тату', 'шт', 3, 0],
      ['Бинты эластичные', 'Основные расходники', 'шт', 3, 0],
      ['Лабрет', 'Лабрет', 'шт', 0, 4],
    ]);
    const movements = db.select().from(stockMovements).all();
    expect(movements).toHaveLength(1);
    expect(movements[0]).toMatchObject({ type: 'receipt', delta: 4, quantityAfter: 4 });
  });

  it('is idempotent and reports invalid rows without aborting the rest', () => {
    const { db } = openDatabase(':memory:');
    importProducts(db, records, opts);

    const second = importProducts(db, [...records, { kind: 'consumable', name: '' }, { kind: 'tool', name: 'Пинцет' }], opts);

    expect(second).toMatchObject({ total: 6, created: 0, existing: 4 });
    expect(second.invalid.map((i) => i.index)).toEqual([4, 5]);
    expect(db.select().from(products).all()).toHaveLength(4);
  });
});
