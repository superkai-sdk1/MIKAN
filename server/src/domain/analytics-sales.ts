import { and, asc, eq, getTableColumns, gte, lt } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { appointments, saleItems, sales } from '../db/schema.js';
import type { SaleItemRow, SaleRow } from '../lib/serialize.js';
import { localDate, localDatesInRange, localWeekdayHour } from '../lib/time.js';

/**
 * Sales of an analytics period. Revenue counts every sale made in the period and subtracts refunds made in it
 * (cash basis, like a shift); the breakdowns (items, masters, clients, hours) count only the sales that were not
 * refunded, so a returned receipt never inflates tops or margins.
 */

/** A sale with the master of the appointment it paid for (`null` when not linked to an appointment). */
export type PeriodSale = SaleRow & { masterId: number | null };

export interface PeriodSales {
  /** Every sale made in the period, refunded later or not. */
  made: PeriodSale[];
  /** The made sales that are still `completed`. */
  kept: PeriodSale[];
  /** Sales refunded during the period, whenever they were made. */
  refunded: SaleRow[];
  /** Items of the kept sales, by sale, ordered by id. */
  itemsBySale: Map<number, SaleItemRow[]>;
}

export function loadPeriodSales(db: DbOrTx, from: number, to: number): PeriodSales {
  const made = db
    .select({ ...getTableColumns(sales), masterId: appointments.masterId })
    .from(sales)
    .leftJoin(appointments, eq(sales.appointmentId, appointments.id))
    .where(and(gte(sales.createdAt, from), lt(sales.createdAt, to)))
    .orderBy(asc(sales.id))
    .all();
  const refunded = db
    .select()
    .from(sales)
    .where(and(eq(sales.status, 'refunded'), gte(sales.refundedAt, from), lt(sales.refundedAt, to)))
    .orderBy(asc(sales.id))
    .all();
  // A join instead of `sale_id in (…)`: a year of receipts would not fit into SQL parameters.
  const items = db
    .select(getTableColumns(saleItems))
    .from(saleItems)
    .innerJoin(sales, eq(saleItems.saleId, sales.id))
    .where(and(gte(sales.createdAt, from), lt(sales.createdAt, to), eq(sales.status, 'completed')))
    .orderBy(asc(saleItems.id))
    .all();
  const itemsBySale = new Map<number, SaleItemRow[]>();
  for (const item of items) itemsBySale.set(item.saleId, [...(itemsBySale.get(item.saleId) ?? []), item]);
  return { made, kept: made.filter((s) => s.status === 'completed'), refunded, itemsBySale };
}

const sumOf = <T>(list: readonly T[], pick: (x: T) => number) => list.reduce((s, x) => s + pick(x), 0);

export function revenueSection(s: PeriodSales) {
  const gross = sumOf(s.made, (x) => x.total);
  const refunds = sumOf(s.refunded, (x) => x.total);
  return {
    gross,
    refunds,
    refundsCount: s.refunded.length,
    net: gross - refunds,
    salesCount: s.made.length,
    averageCheck: s.made.length ? Math.round(gross / s.made.length) : 0,
    discounts: sumOf(s.made, (x) => x.discount),
    kept: sumOf(s.kept, (x) => x.total),
    payments: {
      cash: sumOf(s.made, (x) => x.payCash),
      card: sumOf(s.made, (x) => x.payCard),
      transfer: sumOf(s.made, (x) => x.payTransfer),
      qr: sumOf(s.made, (x) => x.payQr),
      deposit: sumOf(s.made, (x) => x.payDeposit),
    },
  };
}

export type RevenueSection = ReturnType<typeof revenueSection>;

const WEEKDAYS = [1, 2, 3, 4, 5, 6, 7];
const HOURS = Array.from({ length: 24 }, (_, hour) => hour);

/**
 * Every studio-local day of the range (zeros included) with sales made and refunds that day; and the kept sales
 * bucketed by weekday (Mon…Sun) and hour of day.
 */
export function timeSeries(s: PeriodSales, from: number, to: number, tz: string) {
  const days = new Map(localDatesInRange(from, to, tz).map((date) => [date, { date, gross: 0, refunds: 0, net: 0, salesCount: 0 }]));
  for (const sale of s.made) {
    const day = days.get(localDate(sale.createdAt, tz));
    if (!day) continue;
    day.gross += sale.total;
    day.salesCount += 1;
  }
  for (const sale of s.refunded) {
    const day = sale.refundedAt != null ? days.get(localDate(sale.refundedAt, tz)) : undefined;
    if (day) day.refunds += sale.total;
  }
  const byWeekday = WEEKDAYS.map((weekday) => ({ weekday, revenue: 0, salesCount: 0 }));
  const byHour = HOURS.map((hour) => ({ hour, revenue: 0, salesCount: 0 }));
  for (const sale of s.kept) {
    const { weekday, hour } = localWeekdayHour(sale.createdAt, tz);
    for (const bucket of [byWeekday[weekday - 1], byHour[hour]]) {
      if (!bucket) continue;
      bucket.revenue += sale.total;
      bucket.salesCount += 1;
    }
  }
  return {
    byDay: [...days.values()].map((d) => ({ ...d, net: d.gross - d.refunds })),
    byWeekday,
    byHour,
  };
}
