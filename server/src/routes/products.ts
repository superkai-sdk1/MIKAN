import { and, asc, eq, sql } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { products } from '../db/schema.js';
import { createProduct, deleteProduct, hasLowStock, serializeProduct, serializeProducts, updateProduct } from '../domain/products.js';
import { getProductRow, listMovements, recordBatchMovement, recordManualMovement, recordPurchase, serializeMovements } from '../domain/stock.js';
import { createRevision, getRevision, listRevisions } from '../domain/revisions.js';
import { idempotent } from '../lib/idempotency.js';
import { THREAD_TYPES } from '../lib/jewelry.js';
import { normalizeSearchTerm } from '../lib/text.js';
import {
  idParams,
  likePattern,
  money,
  nonNull,
  nullableText,
  pagination,
  parse,
  queryBool,
  queryId,
  requiredText,
} from '../lib/validation.js';

const id = z.number().int().positive();
const kind = z.enum(['jewelry', 'goods', 'consumable']);
const photoPath = z
  .string()
  .trim()
  .max(500)
  .refine((v) => v.startsWith('/uploads/') || /^https?:\/\//.test(v), {
    message: 'ссылка на фото должна начинаться с /uploads/ или http(s)://',
  });
const photoUrl = z
  .union([z.literal(''), photoPath])
  .nullish()
  .transform((v) => (v === '' ? null : v));
const quantity = z.number().int().min(0).max(1_000_000);
const thicknessMm = z
  .number()
  .positive()
  .max(30)
  .refine((v) => Math.abs(v * 100 - Math.round(v * 100)) < 1e-6, { message: 'не больше двух знаков после запятой' })
  .nullish();

const variant = z.object({
  id: id.nullish(),
  name: nullableText(100),
  sku: nullableText(100),
  price: money.nullish(),
  cost: money.nullish(),
  minQuantity: nonNull(quantity),
  initialQuantity: nonNull(quantity),
});

const fields = {
  sku: nullableText(100),
  category: nullableText(100),
  material: nullableText(200),
  threadType: z.enum(THREAD_TYPES).nullish(),
  thicknessMm,
  color: nullableText(100),
  stone: nullableText(100),
  supplier: nullableText(100),
  description: nullableText(5000),
  price: nonNull(money),
  cost: money.nullish(),
  unit: nonNull(requiredText(20)),
  photos: nonNull(z.array(photoPath).max(10)),
  photoUrl,
  serviceIds: nonNull(z.array(id).max(30)),
  stockMode: nonNull(z.enum(['quantity', 'presence'])),
  presenceStatus: z.enum(['ok', 'low', 'out']).nullish(),
  active: nonNull(z.boolean()),
  variants: nonNull(z.array(variant).min(1).max(50)),
  // Older builds describe the only size with these.
  size: nullableText(100),
  minQuantity: nonNull(quantity),
};
const createBody = z.object({ kind, name: requiredText(200), ...fields, initialQuantity: nonNull(quantity) });
const patchBody = z.object({ kind: nonNull(kind), name: nonNull(requiredText(200)), ...fields });
const manualType = z.enum(['receipt', 'writeoff', 'usage', 'adjustment']);
const unitCost = money.nullish();
const movementBody = z.object({ type: manualType, variantId: id.nullish(), quantity, note: nullableText(500), unitCost });
const batchBody = z.object({
  type: manualType,
  note: nullableText(500),
  unitCost,
  lines: z.array(z.object({ variantId: id, quantity, unitCost })).min(1).max(50),
});
const deleteQuery = z.object({ writeOff: queryBool });
const listQuery = z.object({
  kind: kind.optional(),
  search: z.string().trim().max(100).optional(),
  lowStock: queryBool,
  includeInactive: queryBool,
});
const purchaseBody = z.object({
  amount: z.number().int().min(1).max(100_000_000),
  note: nullableText(500),
  presenceStatus: z.enum(['ok', 'low', 'out']).nullish(),
});
const movementTypes = z.enum(['receipt', 'sale', 'return', 'writeoff', 'usage', 'adjustment', 'purchase']);
const revisionBody = z.object({
  section: z.enum(['jewelry', 'goods', 'consumable']).nullish(),
  note: nullableText(500),
  counts: nonNull(z.array(z.object({ variantId: id, quantity })).max(2000)),
  presence: nonNull(z.array(z.object({ productId: id, status: z.enum(['ok', 'low', 'out']) })).max(500)),
});
const sizeQuery = pagination.extend({ variantId: queryId });

export function productRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;

  app.get('/products', async (request) => {
    const q = parse(listQuery, request.query);
    const conditions = [];
    conditions.push(eq(products.archived, false));
    if (!q.includeInactive) conditions.push(eq(products.active, true));
    if (q.kind) conditions.push(eq(products.kind, q.kind));
    if (q.lowStock) conditions.push(hasLowStock);
    if (q.search) conditions.push(sql`${products.searchText} like ${likePattern(normalizeSearchTerm(q.search))} escape '\\'`);
    const rows = db
      .select()
      .from(products)
      .where(conditions.length ? and(...conditions) : undefined)
      .orderBy(asc(products.categorySort), asc(products.nameSort), asc(products.id))
      .all();
    return { items: serializeProducts(db, rows) };
  });

  app.get('/products/:id', async (request) => {
    const { id } = parse(idParams, request.params);
    return serializeProduct(db, getProductRow(db, id));
  });

  app.post('/products', async (request) => {
    const input = parse(createBody, request.body);
    return db.transaction((tx) => serializeProduct(tx, createProduct(tx, input, request.employee.id)));
  });

  app.patch('/products/:id', async (request) => {
    const { id } = parse(idParams, request.params);
    const input = parse(patchBody, request.body);
    return serializeProduct(db, updateProduct(db, id, input, request.employee.id));
  });

  app.post('/products/:id/movements', async (request, reply) => {
    const { id } = parse(idParams, request.params);
    const input = parse(movementBody, request.body);
    return idempotent(db, request, reply, (tx) => {
      const { product, movement } = recordManualMovement(tx, id, input, request.employee.id);
      return { product: serializeProduct(tx, product), movement: serializeMovements(tx, [movement])[0] };
    });
  });

  app.delete('/products/:id', async (request) => {
    const { id } = parse(idParams, request.params);
    const { writeOff } = parse(deleteQuery, request.query);
    return deleteProduct(db, id, { writeOff: writeOff ?? false }, request.employee.id);
  });

  app.post('/products/:id/purchases', async (request, reply) => {
    const { id } = parse(idParams, request.params);
    const input = parse(purchaseBody, request.body);
    return idempotent(db, request, reply, (tx) => {
      const { product, movement } = recordPurchase(tx, id, input, request.employee.id);
      return { product: serializeProduct(tx, product), movement: serializeMovements(tx, [movement])[0] };
    });
  });

  app.post('/products/:id/movements/batch', async (request, reply) => {
    const { id } = parse(idParams, request.params);
    const input = parse(batchBody, request.body);
    return idempotent(db, request, reply, (tx) => {
      const { product, movements } = recordBatchMovement(tx, id, input, request.employee.id);
      return { product: serializeProduct(tx, product), movements: serializeMovements(tx, movements) };
    });
  });

  app.get('/products/:id/movements', async (request) => {
    const { id } = parse(idParams, request.params);
    const q = parse(sizeQuery, request.query);
    getProductRow(db, id);
    return listMovements(db, { productId: id, variantId: q.variantId, limit: q.limit, offset: q.offset });
  });

  app.post('/stock/revisions', async (request, reply) => {
    const input = parse(revisionBody, request.body);
    return idempotent(db, request, reply, (tx) =>
      createRevision(tx, { section: input.section, note: input.note, counts: input.counts ?? [], presence: input.presence ?? [] }, request.employee.id),
    );
  });

  app.get('/stock/revisions', async (request) => {
    const q = parse(pagination, request.query);
    return listRevisions(db, q);
  });

  app.get('/stock/revisions/:id', async (request) => {
    const { id } = parse(idParams, request.params);
    return getRevision(db, id);
  });

  app.get('/stock/movements', async (request) => {
    const q = parse(pagination.extend({ type: movementTypes.optional() }), request.query);
    return listMovements(db, { type: q.type, limit: q.limit, offset: q.offset });
  });
}
