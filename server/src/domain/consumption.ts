import { and, eq } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { stockMovements } from '../db/schema.js';
import type { AppointmentRow } from '../lib/serialize.js';
import { productsByIds, serviceLinesByAppointment } from './refs.js';
import { normsByService } from './services.js';
import { applyMovement, currentVariants, getProductRow, resolveVariant, severalSizesForMovement } from './stock.js';

/** What completing an appointment took from the stock (see API.md, `complete`). */
export interface Consumption {
  used: Array<{ productId: number; productName: string; quantity: number }>;
  shortages: Array<{ productId: number; productName: string; needed: number; deducted: number }>;
}

const NORMS_NOTE = 'Расход по нормам услуг';
const MANUAL_NOTE = 'Расход на процедуру';

export const noConsumption = (): Consumption => ({ used: [], shortages: [] });

/** Usage is recorded once per appointment. */
export function usageRecorded(db: DbOrTx, appointmentId: number): boolean {
  return (
    db
      .select({ id: stockMovements.id })
      .from(stockMovements)
      .where(and(eq(stockMovements.appointmentId, appointmentId), eq(stockMovements.type, 'usage')))
      .get() !== undefined
  );
}

/** Units of each consumable the appointment's procedures use: Σ over its service lines (the legacy service without lines). */
function neededByNorms(db: DbOrTx, appointment: AppointmentRow): Map<number, number> {
  const lines = serviceLinesByAppointment(db, [appointment.id]).get(appointment.id) ?? [];
  const serviceIds = (lines.length ? lines.map((l) => l.serviceId) : [appointment.serviceId]).filter((id): id is number => id != null);
  const norms = normsByService(db, serviceIds);
  const needed = new Map<number, number>();
  for (const serviceId of serviceIds) {
    for (const norm of norms.get(serviceId) ?? []) needed.set(norm.productId, (needed.get(norm.productId) ?? 0) + norm.quantity);
  }
  return needed;
}

/**
 * Deducts the services' norms. Never fails: a consumable short of stock gives what it has and is reported; presence
 * consumables («есть / нет») and archived ones are skipped.
 */
export function applyConsumptionNorms(db: DbOrTx, appointment: AppointmentRow, employeeId: number | null): Consumption {
  const result = noConsumption();
  const needed = neededByNorms(db, appointment);
  const productMap = productsByIds(db, [...needed.keys()]);
  for (const [productId, quantity] of needed) {
    const product = productMap.get(productId);
    if (!product || product.kind !== 'consumable' || product.stockMode === 'presence') continue;
    const size = currentVariants(db, productId)[0];
    if (!size) continue;
    const deducted = Math.min(quantity, size.quantity);
    if (deducted > 0) {
      applyMovement(db, { productId, variantId: size.id, delta: -deducted, type: 'usage', appointmentId: appointment.id, employeeId, note: NORMS_NOTE });
      result.used.push({ productId, productName: product.name, quantity: deducted });
    }
    if (deducted < quantity) result.shortages.push({ productId, productName: product.name, needed: quantity, deducted });
  }
  return result;
}

/** Exactly the consumables staff listed; a shortage is `insufficient_stock`. Presence consumables take no movement. */
export function recordListedUsage(
  db: DbOrTx,
  appointmentId: number,
  items: Array<{ productId: number; variantId?: number | null; quantity: number }>,
  employeeId: number,
): Consumption {
  const result = noConsumption();
  for (const item of items) {
    const product = getProductRow(db, item.productId);
    if (product.stockMode === 'presence') continue;
    const variant = resolveVariant(db, product, item.variantId, severalSizesForMovement(product));
    applyMovement(db, { productId: item.productId, variantId: variant.id, delta: -item.quantity, type: 'usage', appointmentId, employeeId, note: MANUAL_NOTE });
    result.used.push({ productId: product.id, productName: product.name, quantity: item.quantity });
  }
  return result;
}
