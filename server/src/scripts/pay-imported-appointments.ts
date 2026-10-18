/**
 * Records the past visits carried over from YCLIENTS as paid sales: the studio was paid for them in cash, only the
 * bookkeeping lived in YCLIENTS. One sale per visit, dated at the end of the visit, with its client and the master as
 * the seller, paid in cash: one service item per booked service line (catalog service, name and price as booked; when
 * the lines add up to more than the visit price the difference is the discount), or — without lines, or when they add
 * up to less — one item at the visit price named after the lines, else the visit title, else «Процедура».
 *
 *   node dist/scripts/pay-imported-appointments.js --before=2026-10-15 [--apply]
 *
 * `--before` is required: the day the studio started working in MIKAN, so visits made in the app are never touched.
 * A visit qualifies when it started before it, has no sale and is `scheduled`, `confirmed` or `completed` (cancelled
 * ones and no-shows stay as they are). It becomes `completed` (completedAt = its end unless already set) and gets the
 * sale; its pending reminders and prepayment QR codes are cancelled. Visits that hold a prepayment are left for staff
 * and listed. The sales belong to no cash shift (there were none then), so shift balances do not change. Without
 * --apply it is a dry run; re-running is safe.
 */
import path from 'node:path';
import { and, eq, inArray, isNull, lt, max } from 'drizzle-orm';
import { openDatabase, type Db } from '../db/client.js';
import { appointments, saleItems, sales } from '../db/schema.js';
import { depositLedgerByAppointment, heldAmount } from '../domain/deposit-ledger.js';
import { cancelPendingDepositCodes } from '../domain/deposits.js';
import { serviceLinesByAppointment } from '../domain/refs.js';
import { cancelPendingForAppointment } from '../domain/scheduling.js';
import type { AppointmentRow, AppointmentServiceRow } from '../lib/serialize.js';
import { parseInstant, toIso } from '../lib/time.js';
import { isEntryPoint } from './cli.js';

const OPEN_STATUSES = ['scheduled', 'confirmed', 'completed'];
const ITEM_FALLBACK = 'Процедура';
const SALE_NOTE = 'Перенесено из YCLIENTS';

export interface PayImportedSummary {
  before: string;
  matched: number;
  byStatus: Record<string, number>;
  firstStartsAt: string | null;
  lastStartsAt: string | null;
  /** Sum of the sales that are (or would be) recorded. */
  total: number;
  /** Sales recorded by this run. */
  recorded: number;
  /** Visits holding a prepayment: left as they are, staff decide. */
  skippedWithDeposit: number[];
}

export function payImportedAppointments(db: Db, opts: { before: number; apply: boolean; now?: number }): PayImportedSummary {
  const now = opts.now ?? Date.now();
  const rows = db
    .select()
    .from(appointments)
    .where(
      and(
        lt(appointments.startsAt, opts.before),
        isNull(appointments.saleId),
        inArray(appointments.status, OPEN_STATUSES),
      ),
    )
    .orderBy(appointments.startsAt, appointments.id)
    .all();
  const ledgers = depositLedgerByAppointment(db, rows.map((r) => r.id));
  const holding = new Set(rows.filter((r) => heldAmount(ledgers.get(r.id) ?? []) > 0).map((r) => r.id));
  const paying = rows.filter((r) => !holding.has(r.id));
  const byStatus: Record<string, number> = {};
  for (const row of rows) byStatus[row.status] = (byStatus[row.status] ?? 0) + 1;
  const summary: PayImportedSummary = {
    before: toIso(opts.before),
    matched: rows.length,
    byStatus,
    firstStartsAt: toIso(rows[0]?.startsAt ?? null),
    lastStartsAt: toIso(rows.at(-1)?.startsAt ?? null),
    total: paying.reduce((sum, r) => sum + r.price, 0),
    recorded: 0,
    skippedWithDeposit: [...holding],
  };
  if (!opts.apply) return summary;
  const lines = serviceLinesByAppointment(db, paying.map((r) => r.id));
  db.transaction((tx) => {
    let number = tx.select({ n: max(sales.number) }).from(sales).get()?.n ?? 0;
    for (const row of paying) {
      const paidAt = row.completedAt ?? row.endsAt;
      number += 1;
      const { items, subtotal } = saleItemsOf(row, lines.get(row.id) ?? []);
      const sale = tx
        .insert(sales)
        .values({
          number,
          clientId: row.clientId,
          employeeId: row.masterId,
          appointmentId: row.id,
          shiftId: null,
          subtotal,
          discount: subtotal - row.price,
          total: row.price,
          payCash: row.price,
          status: 'completed',
          note: SALE_NOTE,
          createdAt: paidAt,
        })
        .returning()
        .get();
      tx.insert(saleItems)
        .values(items.map((item) => ({ ...item, saleId: sale.id })))
        .run();
      tx.update(appointments)
        .set({ status: 'completed', completedAt: paidAt, saleId: sale.id, updatedAt: now })
        .where(eq(appointments.id, row.id))
        .run();
      cancelPendingForAppointment(tx, row.id, 'reminder');
      cancelPendingDepositCodes(tx, row.id, now);
    }
  });
  summary.recorded = paying.length;
  return summary;
}

interface ServiceItem {
  type: 'service';
  serviceId: number | null;
  name: string;
  quantity: number;
  price: number;
  total: number;
}

/** The sold items of a visit and their sum before the discount (see the header). */
function saleItemsOf(row: AppointmentRow, lines: AppointmentServiceRow[]): { items: ServiceItem[]; subtotal: number } {
  const linesTotal = lines.reduce((sum, l) => sum + l.price, 0);
  if (lines.length > 0 && linesTotal >= row.price) {
    const items = lines.map((l) => ({ type: 'service' as const, serviceId: l.serviceId, name: l.name, quantity: 1, price: l.price, total: l.price }));
    return { items, subtotal: linesTotal };
  }
  const name = lines.map((l) => l.name).join(', ') || row.title?.trim() || ITEM_FALLBACK;
  const serviceId = lines.length === 1 ? lines[0]!.serviceId : row.serviceId;
  return { items: [{ type: 'service', serviceId, name, quantity: 1, price: row.price, total: row.price }], subtotal: row.price };
}

if (isEntryPoint(import.meta.url)) {
  const args = process.argv.slice(2);
  const beforeArg = args.find((a) => a.startsWith('--before='))?.slice('--before='.length);
  const before = beforeArg ? parseInstant(beforeArg.length === 10 ? `${beforeArg}T00:00:00Z` : beforeArg) : null;
  if (before === null) {
    process.stderr.write('Usage: node dist/scripts/pay-imported-appointments.js --before=YYYY-MM-DD[THH:MM:SSZ] [--apply]\n');
    process.exit(2);
  }
  const apply = args.includes('--apply');
  const { db, sqlite } = openDatabase(path.join(process.env.DATA_DIR ?? './data', 'mikan.db'));
  try {
    const summary = payImportedAppointments(db, { before, apply });
    process.stdout.write(`${JSON.stringify({ mode: apply ? 'apply' : 'dry-run', ...summary }, null, 2)}\n`);
  } finally {
    sqlite.close();
  }
}
