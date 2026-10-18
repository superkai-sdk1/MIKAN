import { count, desc, eq, max } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { products, productVariants, stockMovements, stockRevisions } from '../db/schema.js';
import { badRequest, notFound } from '../lib/errors.js';
import type { MovementRow } from '../lib/serialize.js';
import { toIso } from '../lib/time.js';
import { employeeRefOrMissing, employeesByIds } from './refs.js';
import { applyMovement, getProductRow, serializeMovements } from './stock.js';

type RevisionRow = typeof stockRevisions.$inferSelect;
export type PresenceStatus = 'ok' | 'low' | 'out';

export interface RevisionInput {
  section?: string | null;
  note?: string | null;
  /** Counted stock per size. */
  counts: Array<{ variantId: number; quantity: number }>;
  /** Marked status per presence consumable. */
  presence: Array<{ productId: number; status: PresenceStatus }>;
}

interface PresenceChange {
  productId: number;
  productName: string;
  from: string;
  to: string;
}

function parsePresence(json: string): PresenceChange[] {
  try {
    const value: unknown = JSON.parse(json);
    return Array.isArray(value) ? (value as PresenceChange[]) : [];
  } catch {
    return [];
  }
}

function revisionOut(db: DbOrTx, row: RevisionRow, movements: MovementRow[]) {
  const employees = employeesByIds(db, [row.employeeId]);
  return {
    id: row.id,
    number: row.number,
    section: row.section,
    note: row.note,
    employee: employeeRefOrMissing(employees, row.employeeId),
    counted: row.counted,
    changed: row.changed,
    surplus: row.surplus,
    shortage: row.shortage,
    surplusCost: row.surplusCost,
    shortageCost: row.shortageCost,
    presenceChanges: parsePresence(row.presenceJson),
    movements: serializeMovements(db, movements),
    createdAt: toIso(row.createdAt),
  };
}

/**
 * Records a stock count in one transaction: a differing size gets an `adjustment` «Ревизия №N», a presence consumable
 * its marked status. Every line counts as checked, so a count that matches everything still documents the check.
 */
export function createRevision(db: DbOrTx, input: RevisionInput, employeeId: number) {
  return db.transaction((tx) => {
    if (input.counts.length === 0 && input.presence.length === 0) throw badRequest('Ревизия пустая');
    const variantIds = input.counts.map((c) => c.variantId);
    if (new Set(variantIds).size !== variantIds.length) throw badRequest('Размер указан дважды');
    const productIds = input.presence.map((p) => p.productId);
    if (new Set(productIds).size !== productIds.length) throw badRequest('Расходник указан дважды');

    const now = Date.now();
    const number = (tx.select({ n: max(stockRevisions.number) }).from(stockRevisions).get()?.n ?? 0) + 1;
    const revision = tx
      .insert(stockRevisions)
      .values({
        number,
        section: input.section ?? null,
        note: input.note ?? null,
        employeeId,
        counted: input.counts.length + input.presence.length,
        changed: 0,
        surplus: 0,
        shortage: 0,
        surplusCost: 0,
        shortageCost: 0,
        createdAt: now,
      })
      .returning()
      .get();
    const note = input.note ? `Ревизия №${number} · ${input.note}` : `Ревизия №${number}`;
    const stats = { changed: 0, surplus: 0, shortage: 0, surplusCost: 0, shortageCost: 0 };
    const movements: MovementRow[] = [];

    for (const line of input.counts) {
      const variant = tx.select().from(productVariants).where(eq(productVariants.id, line.variantId)).get();
      if (!variant || variant.archived) throw badRequest('Размер не найден');
      const product = getProductRow(tx, variant.productId);
      if (product.stockMode === 'presence') throw badRequest(`«${product.name}» учитывается как «есть / нет» — отметьте наличие`);
      const delta = line.quantity - variant.quantity;
      if (delta === 0) continue;
      const unitCost = variant.cost ?? product.cost ?? 0;
      stats.changed += 1;
      if (delta > 0) {
        stats.surplus += delta;
        stats.surplusCost += delta * unitCost;
      } else {
        stats.shortage += -delta;
        stats.shortageCost += -delta * unitCost;
      }
      movements.push(
        applyMovement(tx, { productId: product.id, variantId: variant.id, delta, type: 'adjustment', note, revisionId: revision.id, employeeId }).movement,
      );
    }

    const changes: PresenceChange[] = [];
    for (const line of input.presence) {
      const product = getProductRow(tx, line.productId);
      if (product.kind !== 'consumable' || product.stockMode !== 'presence') {
        throw badRequest(`«${product.name}» считается в штуках — укажите количество`);
      }
      if (product.presenceStatus === line.status) continue;
      tx.update(products).set({ presenceStatus: line.status, updatedAt: now }).where(eq(products.id, product.id)).run();
      changes.push({ productId: product.id, productName: product.name, from: product.presenceStatus, to: line.status });
      stats.changed += 1;
    }

    const saved = tx
      .update(stockRevisions)
      .set({ ...stats, presenceJson: JSON.stringify(changes) })
      .where(eq(stockRevisions.id, revision.id))
      .returning()
      .get();
    return revisionOut(tx, saved, movements);
  });
}

export function getRevision(db: DbOrTx, id: number) {
  const row = db.select().from(stockRevisions).where(eq(stockRevisions.id, id)).get();
  if (!row) throw notFound('Ревизия не найдена');
  const movements = db.select().from(stockMovements).where(eq(stockMovements.revisionId, id)).orderBy(stockMovements.id).all();
  return revisionOut(db, row, movements);
}

export function listRevisions(db: DbOrTx, page: { limit: number; offset: number }) {
  const rows = db.select().from(stockRevisions).orderBy(desc(stockRevisions.number)).limit(page.limit).offset(page.offset).all();
  const total = db.select({ n: count() }).from(stockRevisions).get()?.n ?? 0;
  return { items: rows.map((row) => revisionOut(db, row, [])), total };
}
