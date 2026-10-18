import { and, count, desc, eq, gt, gte, inArray, isNotNull, lt, sql } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { cashOperations, cashShifts, products, productVariants, stockMovements } from '../db/schema.js';
import { toIso } from '../lib/time.js';
import { ANALYTICS_TOP_LIMIT } from './analytics-items.js';
import { employeeRefOrMissing, employeesByIds } from './refs.js';

/** Stock expenses and value, and the cash register of an analytics period. */

const SHIFTS_LIMIT = 20;
const EXPENSE_TYPES = ['writeoff', 'usage'] as const;
type ExpenseType = (typeof EXPENSE_TYPES)[number];

/** Current cost of a unit of a size: its own cost, else the product's (SQL). */
const unitCost = sql<number | null>`coalesce(${productVariants.cost}, ${products.cost})`;

interface ExpenseSums {
  quantity: number;
  value: number;
  unitsWithoutCost: number;
}

/** Write-offs and consumables used in procedures during the period, valued at the current unit cost. */
export function stockExpenses(db: DbOrTx, from: number, to: number) {
  const removed = sql<number>`-${stockMovements.delta}`;
  const rows = db
    .select({
      productId: stockMovements.productId,
      name: products.name,
      kind: products.kind,
      type: stockMovements.type,
      quantity: sql<number>`coalesce(sum(${removed}), 0)`,
      value: sql<number>`coalesce(sum(${removed} * ${unitCost}), 0)`,
      unitsWithoutCost: sql<number>`coalesce(sum(case when ${unitCost} is null then ${removed} else 0 end), 0)`,
    })
    .from(stockMovements)
    .innerJoin(productVariants, eq(stockMovements.variantId, productVariants.id))
    .innerJoin(products, eq(stockMovements.productId, products.id))
    .where(and(inArray(stockMovements.type, [...EXPENSE_TYPES]), gte(stockMovements.createdAt, from), lt(stockMovements.createdAt, to)))
    .groupBy(stockMovements.productId, stockMovements.type)
    .all();
  const totals = (type: ExpenseType): ExpenseSums =>
    rows
      .filter((r) => r.type === type)
      .reduce(
        (s, r) => ({ quantity: s.quantity + r.quantity, value: s.value + r.value, unitsWithoutCost: s.unitsWithoutCost + r.unitsWithoutCost }),
        { quantity: 0, value: 0, unitsWithoutCost: 0 },
      );
  const writeoffs = totals('writeoff');
  const usage = totals('usage');
  return {
    writeoffs,
    usage,
    expenses: writeoffs.value + usage.value,
    top: rows
      .map((r) => ({ productId: r.productId, name: r.name, kind: r.kind, type: r.type, quantity: r.quantity, value: r.value }))
      .sort((a, b) => b.value - a.value || b.quantity - a.quantity || a.productId - b.productId)
      .slice(0, ANALYTICS_TOP_LIMIT),
  };
}

export type StockExpenses = ReturnType<typeof stockExpenses>;

/** Stock on hand now (inactive products included): units and their value at the current cost, by product kind. */
export function stockOnHand(db: DbOrTx) {
  const byKind = db
    .select({
      kind: products.kind,
      units: sql<number>`coalesce(sum(${productVariants.quantity}), 0)`,
      value: sql<number>`coalesce(sum(${productVariants.quantity} * ${unitCost}), 0)`,
      unitsWithoutCost: sql<number>`coalesce(sum(case when ${unitCost} is null then ${productVariants.quantity} else 0 end), 0)`,
    })
    .from(productVariants)
    .innerJoin(products, eq(productVariants.productId, products.id))
    .where(gt(productVariants.quantity, 0))
    .groupBy(products.kind)
    .all()
    .sort((a, b) => b.value - a.value || a.kind.localeCompare(b.kind));
  return {
    units: byKind.reduce((s, k) => s + k.units, 0),
    value: byKind.reduce((s, k) => s + k.value, 0),
    unitsWithoutCost: byKind.reduce((s, k) => s + k.unitsWithoutCost, 0),
    byKind,
  };
}

/**
 * Cash in / out operations of the period and the discrepancies of the shifts closed in it: at close
 * (`closingCash − expectedCash`) and at open (`openingCash −` what the previous shift left in the drawer).
 */
export function cashSection(db: DbOrTx, from: number, to: number) {
  const ops = db
    .select({ type: cashOperations.type, n: count(), amount: sql<number>`coalesce(sum(${cashOperations.amount}), 0)` })
    .from(cashOperations)
    .where(and(gte(cashOperations.createdAt, from), lt(cashOperations.createdAt, to)))
    .groupBy(cashOperations.type)
    .all();
  // At most one shift is open at a time, so the shift before is the one with the previous id. Column names are
  // spelled out: drizzle leaves them unqualified in a single-table select, which a subquery would misread.
  const previousClosing = sql<number | null>`(select prev.closing_cash from cash_shifts prev where prev.id < cash_shifts.id order by prev.id desc limit 1)`;
  const shifts = db
    .select({
      id: cashShifts.id,
      openedAt: cashShifts.openedAt,
      closedAt: cashShifts.closedAt,
      closedById: cashShifts.closedById,
      openingCash: cashShifts.openingCash,
      closingCash: cashShifts.closingCash,
      expectedCash: cashShifts.expectedCash,
      previousClosing,
    })
    .from(cashShifts)
    .where(and(isNotNull(cashShifts.closedAt), gte(cashShifts.closedAt, from), lt(cashShifts.closedAt, to)))
    .orderBy(desc(cashShifts.closedAt), desc(cashShifts.id))
    .all()
    .map((s) => ({
      ...s,
      difference: s.closingCash != null && s.expectedCash != null ? s.closingCash - s.expectedCash : 0,
      openingDifference: s.previousClosing != null ? s.openingCash - s.previousClosing : null,
    }));
  const differences = shifts.map((s) => s.difference);
  const flagged = shifts.filter((s) => s.difference !== 0 || (s.openingDifference ?? 0) !== 0).slice(0, SHIFTS_LIMIT);
  const emps = employeesByIds(db, flagged.map((s) => s.closedById));
  const opsOf = (type: string) => ops.find((o) => o.type === type);
  return {
    cashIn: opsOf('in')?.amount ?? 0,
    cashOut: opsOf('out')?.amount ?? 0,
    operationsCount: ops.reduce((s, o) => s + o.n, 0),
    shiftsClosed: shifts.length,
    closingDifference: differences.reduce((s, d) => s + d, 0),
    shortage: differences.filter((d) => d < 0).reduce((s, d) => s + d, 0),
    surplus: differences.filter((d) => d > 0).reduce((s, d) => s + d, 0),
    openingDifference: shifts.reduce((s, x) => s + (x.openingDifference ?? 0), 0),
    shifts: flagged.map((s) => ({
      id: s.id,
      openedAt: toIso(s.openedAt),
      closedAt: toIso(s.closedAt),
      closedBy: employeeRefOrMissing(emps, s.closedById),
      openingCash: s.openingCash,
      closingCash: s.closingCash,
      expectedCash: s.expectedCash,
      openingDifference: s.openingDifference,
      difference: s.difference,
    })),
  };
}
