/**
 * Closes the past visits carried over from YCLIENTS as paid: they were paid there, so MIKAN must not show them as
 * awaiting payment (nor take payment for them again).
 *
 *   node dist/scripts/close-imported-appointments.js [--before=2026-10-15] [--apply]
 *
 * A visit qualifies when it started before `--before` (default: now), has no sale and is not marked paid yet, is
 * `scheduled`, `confirmed` or `completed`, and has the shape the YCLIENTS import gives (no catalog service, no service
 * lines). It becomes `completed` (completedAt = its end unless already set) with `paidOutside = true`; its pending
 * reminders and prepayment QR codes are cancelled. Visits that hold a prepayment are left for staff and listed.
 * Without --apply it is a dry run. Re-running is safe: closed visits no longer qualify.
 */
import path from 'node:path';
import { and, eq, inArray, isNull, lt, notExists } from 'drizzle-orm';
import { openDatabase, type Db } from '../db/client.js';
import { appointments, appointmentServices } from '../db/schema.js';
import { depositLedgerByAppointment, heldAmount } from '../domain/deposit-ledger.js';
import { cancelPendingDepositCodes } from '../domain/deposits.js';
import { cancelPendingForAppointment } from '../domain/scheduling.js';
import { parseInstant, toIso } from '../lib/time.js';
import { isEntryPoint } from './cli.js';

const OPEN_STATUSES = ['scheduled', 'confirmed', 'completed'];

export interface CloseImportedSummary {
  before: string;
  matched: number;
  byStatus: Record<string, number>;
  firstStartsAt: string | null;
  lastStartsAt: string | null;
  totalPrice: number;
  closed: number;
  /** Visits holding a prepayment: left as they are, staff decide. */
  skippedWithDeposit: number[];
}

export function closeImportedAppointments(db: Db, opts: { before: number; apply: boolean; now?: number }): CloseImportedSummary {
  const now = opts.now ?? Date.now();
  const rows = db
    .select()
    .from(appointments)
    .where(
      and(
        lt(appointments.startsAt, opts.before),
        isNull(appointments.saleId),
        eq(appointments.paidOutside, false),
        isNull(appointments.serviceId),
        inArray(appointments.status, OPEN_STATUSES),
        notExists(db.select({ id: appointmentServices.id }).from(appointmentServices).where(eq(appointmentServices.appointmentId, appointments.id))),
      ),
    )
    .orderBy(appointments.startsAt)
    .all();
  const ledgers = depositLedgerByAppointment(db, rows.map((r) => r.id));
  const holding = new Set(rows.filter((r) => heldAmount(ledgers.get(r.id) ?? []) > 0).map((r) => r.id));
  const closing = rows.filter((r) => !holding.has(r.id));
  const byStatus: Record<string, number> = {};
  for (const row of rows) byStatus[row.status] = (byStatus[row.status] ?? 0) + 1;
  const summary: CloseImportedSummary = {
    before: toIso(opts.before)!,
    matched: rows.length,
    byStatus,
    firstStartsAt: toIso(rows[0]?.startsAt ?? null),
    lastStartsAt: toIso(rows.at(-1)?.startsAt ?? null),
    totalPrice: closing.reduce((sum, r) => sum + r.price, 0),
    closed: 0,
    skippedWithDeposit: [...holding],
  };
  if (!opts.apply) return summary;
  db.transaction((tx) => {
    for (const row of closing) {
      tx.update(appointments)
        .set({ status: 'completed', completedAt: row.completedAt ?? row.endsAt, paidOutside: true, updatedAt: now })
        .where(eq(appointments.id, row.id))
        .run();
      cancelPendingForAppointment(tx, row.id, 'reminder');
      cancelPendingDepositCodes(tx, row.id, now);
    }
  });
  summary.closed = closing.length;
  return summary;
}

if (isEntryPoint(import.meta.url)) {
  const args = process.argv.slice(2);
  const beforeArg = args.find((a) => a.startsWith('--before='))?.slice('--before='.length);
  const before = beforeArg ? parseInstant(beforeArg.length === 10 ? `${beforeArg}T00:00:00Z` : beforeArg) : Date.now();
  if (before === null) {
    process.stderr.write('Usage: node dist/scripts/close-imported-appointments.js [--before=YYYY-MM-DD] [--apply]\n');
    process.exit(2);
  }
  const apply = args.includes('--apply');
  const { db, sqlite } = openDatabase(path.join(process.env.DATA_DIR ?? './data', 'mikan.db'));
  try {
    const summary = closeImportedAppointments(db, { before, apply });
    process.stdout.write(`${JSON.stringify({ mode: apply ? 'apply' : 'dry-run', ...summary }, null, 2)}\n`);
  } finally {
    sqlite.close();
  }
}
