import { and, asc, eq, inArray } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { products, productServices, serviceConsumables } from '../db/schema.js';
import { badRequest } from '../lib/errors.js';
import { serviceOut, type ServiceRow } from '../lib/serialize.js';

export interface NormInput {
  productId: number;
  quantity: number;
}

/** A consumable one procedure of the service uses; presence consumables always read `quantity: 1`. */
export interface ServiceNorm {
  productId: number;
  quantity: number;
}

/** Compatible jewelry and consumption norms of the given services. */
function serviceLinks(db: DbOrTx, serviceIds: number[]) {
  const jewelry = new Map<number, number[]>();
  const norms = new Map<number, ServiceNorm[]>();
  if (serviceIds.length === 0) return { jewelry, norms };
  for (const row of db
    .select({ serviceId: productServices.serviceId, productId: productServices.productId })
    .from(productServices)
    .innerJoin(products, eq(products.id, productServices.productId))
    .where(and(inArray(productServices.serviceId, serviceIds), eq(products.kind, 'jewelry')))
    .orderBy(asc(productServices.productId))
    .all()) {
    jewelry.set(row.serviceId, [...(jewelry.get(row.serviceId) ?? []), row.productId]);
  }
  for (const row of db
    .select({ serviceId: serviceConsumables.serviceId, productId: serviceConsumables.productId, quantity: serviceConsumables.quantity, mode: products.stockMode })
    .from(serviceConsumables)
    .innerJoin(products, eq(products.id, serviceConsumables.productId))
    .where(inArray(serviceConsumables.serviceId, serviceIds))
    .orderBy(asc(products.nameSort), asc(products.id))
    .all()) {
    const norm = { productId: row.productId, quantity: row.mode === 'presence' ? 1 : row.quantity };
    norms.set(row.serviceId, [...(norms.get(row.serviceId) ?? []), norm]);
  }
  return { jewelry, norms };
}

export function serializeServices(db: DbOrTx, rows: ServiceRow[]) {
  const { jewelry, norms } = serviceLinks(db, rows.map((r) => r.id));
  return rows.map((row) => ({ ...serviceOut(row), jewelryIds: jewelry.get(row.id) ?? [], consumables: norms.get(row.id) ?? [] }));
}

export function serializeService(db: DbOrTx, row: ServiceRow) {
  return serializeServices(db, [row])[0]!;
}

/** Norms of the given services keyed by service id (the completion consumes them). */
export function normsByService(db: DbOrTx, serviceIds: number[]): Map<number, ServiceNorm[]> {
  return serviceLinks(db, [...new Set(serviceIds)]).norms;
}

function productKinds(db: DbOrTx, ids: number[]) {
  if (ids.length === 0) return new Map<number, string>();
  return new Map(db.select({ id: products.id, kind: products.kind }).from(products).where(inArray(products.id, ids)).all().map((r) => [r.id, r.kind]));
}

/** Replaces the jewelry compatible with the service (links to other kinds stay). */
export function setCompatibleJewelry(db: DbOrTx, serviceId: number, jewelryIds: number[]): void {
  const ids = [...new Set(jewelryIds)];
  const kinds = productKinds(db, ids);
  if (ids.some((id) => kinds.get(id) !== 'jewelry')) throw badRequest('Украшение не найдено');
  const current = db
    .select({ productId: productServices.productId })
    .from(productServices)
    .innerJoin(products, eq(products.id, productServices.productId))
    .where(and(eq(productServices.serviceId, serviceId), eq(products.kind, 'jewelry')))
    .all()
    .map((r) => r.productId);
  if (current.length) {
    db.delete(productServices).where(and(eq(productServices.serviceId, serviceId), inArray(productServices.productId, current))).run();
  }
  if (ids.length) db.insert(productServices).values(ids.map((productId) => ({ productId, serviceId }))).run();
}

/** Replaces the consumption norm of one procedure of the service. */
export function setConsumptionNorms(db: DbOrTx, serviceId: number, norms: NormInput[]): void {
  const ids = norms.map((n) => n.productId);
  if (new Set(ids).size !== ids.length) throw badRequest('Расходник указан дважды');
  const kinds = productKinds(db, ids);
  if (ids.some((id) => kinds.get(id) !== 'consumable')) throw badRequest('Расходник не найден');
  db.delete(serviceConsumables).where(eq(serviceConsumables.serviceId, serviceId)).run();
  if (norms.length) db.insert(serviceConsumables).values(norms.map((n) => ({ serviceId, productId: n.productId, quantity: n.quantity }))).run();
}
