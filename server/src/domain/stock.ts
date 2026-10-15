import { and, count, desc, eq } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { products, stockMovements } from '../db/schema.js';
import { badRequest, insufficientStock, notFound } from '../lib/errors.js';
import { movementOut, type MovementRow, type ProductRow } from '../lib/serialize.js';
import { employeeRefOrMissing, employeesByIds, productsByIds } from './refs.js';

export type MovementType = 'receipt' | 'sale' | 'return' | 'writeoff' | 'usage' | 'adjustment';
export type ManualMovementType = 'receipt' | 'writeoff' | 'usage' | 'adjustment';

export interface MovementInput {
  productId: number;
  delta: number;
  type: MovementType;
  note?: string | null;
  saleId?: number | null;
  appointmentId?: number | null;
  employeeId?: number | null;
}

export function getProductRow(db: DbOrTx, id: number): ProductRow {
  const row = db.select().from(products).where(eq(products.id, id)).get();
  if (!row) throw notFound('Товар не найден');
  return row;
}

export function insufficientMessage(product: ProductRow): string {
  return `Недостаточно на складе: ${product.name} (осталось ${product.quantity})`;
}

/**
 * Applies a stock delta and records the movement. Must run inside a transaction when combined
 * with other writes. Throws `insufficient_stock` if the result would be negative.
 */
export function applyMovement(db: DbOrTx, input: MovementInput): { product: ProductRow; movement: MovementRow } {
  const product = getProductRow(db, input.productId);
  const quantityAfter = product.quantity + input.delta;
  if (quantityAfter < 0) throw insufficientStock(insufficientMessage(product));
  const now = Date.now();
  const updated = db
    .update(products)
    .set({ quantity: quantityAfter, updatedAt: now })
    .where(eq(products.id, product.id))
    .returning()
    .get();
  const movement = db
    .insert(stockMovements)
    .values({
      productId: product.id,
      delta: input.delta,
      quantityAfter,
      type: input.type,
      note: input.note ?? null,
      saleId: input.saleId ?? null,
      appointmentId: input.appointmentId ?? null,
      employeeId: input.employeeId ?? null,
      createdAt: now,
    })
    .returning()
    .get();
  return { product: updated, movement };
}

/** Converts the API's movement `quantity` semantics into a signed delta. */
export function deltaFor(type: ManualMovementType, quantity: number, current: number): number {
  switch (type) {
    case 'receipt':
      if (quantity <= 0) throw badRequest('«Количество»: должно быть больше 0');
      return quantity;
    case 'writeoff':
    case 'usage':
      if (quantity <= 0) throw badRequest('«Количество»: должно быть больше 0');
      return -quantity;
    case 'adjustment':
      if (quantity < 0) throw badRequest('«Количество»: остаток не может быть отрицательным');
      return quantity - current;
  }
}

export function recordManualMovement(
  db: DbOrTx,
  productId: number,
  input: { type: ManualMovementType; quantity: number; note?: string | null },
  employeeId: number,
) {
  return db.transaction((tx) => {
    const product = getProductRow(tx, productId);
    const delta = deltaFor(input.type, input.quantity, product.quantity);
    return applyMovement(tx, { productId, delta, type: input.type, note: input.note, employeeId });
  });
}

export function serializeMovements(db: DbOrTx, rows: MovementRow[]) {
  const prods = productsByIds(
    db,
    rows.map((r) => r.productId),
  );
  const emps = employeesByIds(
    db,
    rows.map((r) => r.employeeId),
  );
  return rows.map((m) =>
    movementOut(m, prods.get(m.productId)?.name ?? 'Удалённый товар', employeeRefOrMissing(emps, m.employeeId)),
  );
}

export function listMovements(
  db: DbOrTx,
  filter: { productId?: number; type?: string; limit: number; offset: number },
) {
  const conditions = [];
  if (filter.productId !== undefined) conditions.push(eq(stockMovements.productId, filter.productId));
  if (filter.type) conditions.push(eq(stockMovements.type, filter.type));
  const where = conditions.length ? and(...conditions) : undefined;
  const rows = db
    .select()
    .from(stockMovements)
    .where(where)
    .orderBy(desc(stockMovements.createdAt), desc(stockMovements.id))
    .limit(filter.limit)
    .offset(filter.offset)
    .all();
  const total = db.select({ n: count() }).from(stockMovements).where(where).get()?.n ?? 0;
  return { items: serializeMovements(db, rows), total };
}
