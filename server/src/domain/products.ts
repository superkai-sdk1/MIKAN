import type { DbOrTx } from '../db/client.js';
import { products } from '../db/schema.js';
import type { ProductRow } from '../lib/serialize.js';
import { searchKey } from '../lib/text.js';
import { applyMovement } from './stock.js';

export interface NewProduct {
  kind: 'jewelry' | 'consumable';
  name: string;
  sku?: string | null;
  category?: string | null;
  material?: string | null;
  size?: string | null;
  description?: string | null;
  price?: number;
  cost?: number | null;
  minQuantity?: number;
  unit?: string;
  photoUrl?: string | null;
  active?: boolean;
  initialQuantity?: number;
}

/** Sort and search columns derived from the product's text fields. */
export function productSearchFields(p: Pick<ProductRow, 'name' | 'sku' | 'category' | 'material' | 'size'>) {
  return {
    nameSort: searchKey(p.name),
    categorySort: searchKey(p.category),
    searchText: searchKey(p.name, p.sku, p.category, p.material, p.size),
  };
}

/** Inserts a product; a positive `initialQuantity` is recorded as a `receipt` movement. Call inside a transaction. */
export function createProduct(db: DbOrTx, input: NewProduct, employeeId: number | null, receiptNote = 'Начальный остаток'): ProductRow {
  const now = Date.now();
  const base = {
    name: input.name,
    sku: input.sku ?? null,
    category: input.category ?? null,
    material: input.material ?? null,
    size: input.size ?? null,
  };
  const created = db
    .insert(products)
    .values({
      ...base,
      ...productSearchFields(base),
      kind: input.kind,
      description: input.description ?? null,
      price: input.price ?? 0,
      cost: input.cost ?? null,
      quantity: 0,
      minQuantity: input.minQuantity ?? 0,
      unit: input.unit ?? 'шт',
      photoUrl: input.photoUrl ?? null,
      active: input.active ?? true,
      createdAt: now,
      updatedAt: now,
    })
    .returning()
    .get();
  if ((input.initialQuantity ?? 0) <= 0) return created;
  return applyMovement(db, {
    productId: created.id,
    delta: input.initialQuantity!,
    type: 'receipt',
    note: receiptNote,
    employeeId,
  }).product;
}
