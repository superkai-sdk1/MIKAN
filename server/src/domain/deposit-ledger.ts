import { and, asc, desc, eq, inArray } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { depositOperations, qrPayments } from '../db/schema.js';
import type { DepositOperationRow, QrPaymentRow } from '../lib/serialize.js';

/**
 * The prepayment ledger read side: pure arithmetic over an appointment's operations plus batch loaders used by
 * serialization. Writes live in `deposits.ts`.
 */

export const DEPOSIT_METHODS = ['cash', 'card', 'transfer', 'qr'] as const;
export type DepositMethod = (typeof DEPOSIT_METHODS)[number];

export const DEPOSIT_OPERATION_TYPES = ['receive', 'apply', 'unapply', 'refund', 'retain'] as const;
export type DepositOperationType = (typeof DEPOSIT_OPERATION_TYPES)[number];

export type DepositStatus = 'none' | 'waiting' | 'paid' | 'applied' | 'refunded' | 'retained';

/** Appointment statuses in which a prepayment is still expected (and can be taken). */
export const DEPOSIT_OPEN_STATUSES = ['scheduled', 'confirmed'];

export type DepositTotals = Record<DepositOperationType, number>;

type LedgerEntry = Pick<DepositOperationRow, 'type' | 'amount'>;

export function depositTotals(ops: readonly LedgerEntry[]): DepositTotals {
  const totals: DepositTotals = { receive: 0, apply: 0, unapply: 0, refund: 0, retain: 0 };
  for (const op of ops) {
    if (op.type in totals) totals[op.type as DepositOperationType] += op.amount;
  }
  return totals;
}

/** Money held for the appointment now: received − applied + returned by sale refunds − refunded − retained. */
export function heldAmount(ops: readonly LedgerEntry[]): number {
  const t = depositTotals(ops);
  return t.receive - t.apply + t.unapply - t.refund - t.retain;
}

/**
 * `paid` while anything is held; otherwise what happened to the money (`applied` → `retained` → `refunded`);
 * with no money ever received, `waiting` for an open appointment that requires a prepayment, else `none`.
 */
export function depositStatusOf(ops: readonly LedgerEntry[], required: number, appointmentStatus: string): DepositStatus {
  const t = depositTotals(ops);
  if (heldAmount(ops) > 0) return 'paid';
  if (t.apply - t.unapply > 0) return 'applied';
  if (t.retain > 0) return 'retained';
  if (t.refund > 0) return 'refunded';
  return required > 0 && DEPOSIT_OPEN_STATUSES.includes(appointmentStatus) ? 'waiting' : 'none';
}

/** The ledger of each given appointment, oldest first. */
export function depositLedgerByAppointment(db: DbOrTx, appointmentIds: number[]): Map<number, DepositOperationRow[]> {
  const result = new Map<number, DepositOperationRow[]>();
  const ids = [...new Set(appointmentIds)];
  if (ids.length === 0) return result;
  const rows = db
    .select()
    .from(depositOperations)
    .where(inArray(depositOperations.appointmentId, ids))
    .orderBy(asc(depositOperations.appointmentId), asc(depositOperations.id))
    .all();
  for (const row of rows) {
    const list = result.get(row.appointmentId) ?? [];
    list.push(row);
    result.set(row.appointmentId, list);
  }
  return result;
}

export function appointmentLedger(db: DbOrTx, appointmentId: number): DepositOperationRow[] {
  return db
    .select()
    .from(depositOperations)
    .where(eq(depositOperations.appointmentId, appointmentId))
    .orderBy(asc(depositOperations.id))
    .all();
}

/** The latest prepayment QR code of each given appointment (any status). */
export function latestDepositCodes(db: DbOrTx, appointmentIds: number[]): Map<number, QrPaymentRow> {
  const result = new Map<number, QrPaymentRow>();
  const ids = [...new Set(appointmentIds)];
  if (ids.length === 0) return result;
  const rows = db
    .select()
    .from(qrPayments)
    .where(and(eq(qrPayments.kind, 'deposit'), inArray(qrPayments.appointmentId, ids)))
    .orderBy(desc(qrPayments.id))
    .all();
  for (const row of rows) {
    if (row.appointmentId != null && !result.has(row.appointmentId)) result.set(row.appointmentId, row);
  }
  return result;
}

/** The method of the latest `receive` (the default way to give the money back). */
export function lastReceiveMethod(ops: readonly DepositOperationRow[]): DepositMethod | null {
  for (let i = ops.length - 1; i >= 0; i--) {
    const op = ops[i]!;
    if (op.type === 'receive' && op.method) return op.method as DepositMethod;
  }
  return null;
}
