import { sql } from 'drizzle-orm';
import { sales } from '../db/schema.js';
import type { SaleItemRow, SaleRow } from '../lib/serialize.js';

/**
 * What of a sale is revenue (docs/API.md «Loyalty bonuses», «Gift certificates», «Analytics»): a gift certificate
 * sold is money received for later, not revenue; bonuses paid are a discount. Paying with a certificate is revenue of
 * the sale it pays.
 */

/**
 * Splits the sale discount across items proportionally to their totals (whole rubles);
 * the rounding remainder goes to the last item so item revenues sum exactly to the sale total.
 */
export function allocateDiscount(items: Array<Pick<SaleItemRow, 'total'>>, discount: number): number[] {
  const subtotal = items.reduce((s, i) => s + i.total, 0);
  if (subtotal === 0 || discount === 0) return items.map((i) => i.total);
  let allocated = 0;
  return items.map((item, index) => {
    const share = index === items.length - 1 ? discount - allocated : Math.round((discount * item.total) / subtotal);
    allocated += share;
    return item.total - share;
  });
}

/** Stored `sale_items.type` of a gift certificate line (sent to the apps as `service` with `certificateId`). */
export const CERTIFICATE_LINE = 'certificate';

export const isCertificateLine = (item: Pick<SaleItemRow, 'type'>): boolean => item.type === CERTIFICATE_LINE;

/**
 * Revenue of each line, in order: certificate lines earn 0; the other lines share the sale discount and the bonus
 * payment proportionally (whole rubles, the remainder to the last such line), so they add up to the sale's revenue.
 * A sale without certificates or bonuses splits exactly like `allocateDiscount`.
 */
export function lineRevenues(
  sale: Pick<SaleRow, 'discount' | 'payBonus'>,
  items: Array<Pick<SaleItemRow, 'type' | 'total'>>,
): number[] {
  const regular = items.filter((item) => !isCertificateLine(item));
  const shared = allocateDiscount(regular, sale.discount + sale.payBonus);
  let next = 0;
  return items.map((item) => (isCertificateLine(item) ? 0 : (shared[next++] ?? 0)));
}

/** Σ totals of a sale's certificate lines (they never take a share of the discount). */
export const certificateLinesTotal = (items: Array<Pick<SaleItemRow, 'type' | 'total'>>): number =>
  items.filter(isCertificateLine).reduce((sum, item) => sum + item.total, 0);

/** SQL for a sale row's revenue: `total − payBonus − its certificate lines`. */
export const saleRevenueSql = sql<number>`(${sales.total} - ${sales.payBonus} - coalesce((select sum(si.total) from sale_items si where si.sale_id = ${sales.id} and si.type = ${CERTIFICATE_LINE}), 0))`;

/** SQL for the money a sale brought into the till now: everything except bonuses and certificate payments. */
export const saleMoneySql = sql<number>`(${sales.total} - ${sales.payBonus} - ${sales.payCertificate})`;
