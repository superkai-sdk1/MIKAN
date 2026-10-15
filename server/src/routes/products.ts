import { and, asc, eq, sql } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { products } from '../db/schema.js';
import { createProduct, productSearchFields } from '../domain/products.js';
import { getProductRow, listMovements, recordManualMovement, serializeMovements } from '../domain/stock.js';
import { idempotent } from '../lib/idempotency.js';
import { productOut, type ProductRow } from '../lib/serialize.js';
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
  requiredText,
} from '../lib/validation.js';

const kind = z.enum(['jewelry', 'consumable']);
const photoUrl = z
  .string()
  .trim()
  .max(500)
  .refine((v) => v === '' || v.startsWith('/uploads/') || /^https?:\/\//.test(v), {
    message: 'ссылка на фото должна начинаться с /uploads/ или http(s)://',
  })
  .nullish()
  .transform((v) => (v === '' ? null : v));
const quantity = z.number().int().min(0).max(1_000_000);

const textFields = {
  sku: nullableText(100),
  category: nullableText(100),
  material: nullableText(200),
  size: nullableText(100),
  description: nullableText(5000),
  photoUrl,
};
const createBody = z.object({
  kind,
  name: requiredText(200),
  ...textFields,
  price: nonNull(money),
  cost: money.nullish(),
  minQuantity: nonNull(quantity),
  unit: nonNull(requiredText(20)),
  active: nonNull(z.boolean()),
  initialQuantity: nonNull(quantity),
});
const patchBody = z.object({
  kind: nonNull(kind),
  name: nonNull(requiredText(200)),
  ...textFields,
  price: nonNull(money),
  cost: money.nullish(),
  minQuantity: nonNull(quantity),
  unit: nonNull(requiredText(20)),
  active: nonNull(z.boolean()),
});
const movementBody = z.object({
  type: z.enum(['receipt', 'writeoff', 'usage', 'adjustment']),
  quantity,
  note: nullableText(500),
});
const listQuery = z.object({
  kind: kind.optional(),
  search: z.string().trim().max(100).optional(),
  lowStock: queryBool,
  includeInactive: queryBool,
});
const movementTypes = z.enum(['receipt', 'sale', 'return', 'writeoff', 'usage', 'adjustment']);

export function productRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;

  app.get('/products', async (request) => {
    const q = parse(listQuery, request.query);
    const conditions = [];
    if (!q.includeInactive) conditions.push(eq(products.active, true));
    if (q.kind) conditions.push(eq(products.kind, q.kind));
    if (q.lowStock) conditions.push(sql`${products.quantity} <= ${products.minQuantity}`);
    if (q.search) conditions.push(sql`${products.searchText} like ${likePattern(normalizeSearchTerm(q.search))} escape '\\'`);
    const rows = db
      .select()
      .from(products)
      .where(conditions.length ? and(...conditions) : undefined)
      .orderBy(asc(products.categorySort), asc(products.nameSort), asc(products.id))
      .all();
    return { items: rows.map(productOut) };
  });

  app.get('/products/:id', async (request) => {
    const { id } = parse(idParams, request.params);
    return productOut(getProductRow(db, id));
  });

  app.post('/products', async (request) => {
    const input = parse(createBody, request.body);
    const row = db.transaction((tx) => createProduct(tx, input, request.employee.id));
    return productOut(row);
  });

  app.patch('/products/:id', async (request) => {
    const { id } = parse(idParams, request.params);
    const input = parse(patchBody, request.body);
    const current = getProductRow(db, id);
    const pick = <K extends keyof typeof input & keyof ProductRow>(k: K) =>
      (input[k] === undefined ? current[k] : input[k]) as ProductRow[K];
    const base = {
      name: input.name ?? current.name,
      sku: pick('sku'),
      category: pick('category'),
      material: pick('material'),
      size: pick('size'),
    };
    const row = db
      .update(products)
      .set({
        ...base,
        ...productSearchFields(base),
        kind: input.kind ?? current.kind,
        description: pick('description'),
        price: input.price ?? current.price,
        cost: pick('cost'),
        minQuantity: input.minQuantity ?? current.minQuantity,
        unit: input.unit ?? current.unit,
        photoUrl: pick('photoUrl'),
        active: input.active ?? current.active,
        updatedAt: Date.now(),
      })
      .where(eq(products.id, id))
      .returning()
      .get();
    return productOut(row);
  });

  app.post('/products/:id/movements', async (request, reply) => {
    const { id } = parse(idParams, request.params);
    const input = parse(movementBody, request.body);
    return idempotent(db, request, reply, (tx) => {
      const { product, movement } = recordManualMovement(tx, id, input, request.employee.id);
      return { product: productOut(product), movement: serializeMovements(tx, [movement])[0] };
    });
  });

  app.get('/products/:id/movements', async (request) => {
    const { id } = parse(idParams, request.params);
    const q = parse(pagination, request.query);
    getProductRow(db, id);
    return listMovements(db, { productId: id, limit: q.limit, offset: q.offset });
  });

  app.get('/stock/movements', async (request) => {
    const q = parse(pagination.extend({ type: movementTypes.optional() }), request.query);
    return listMovements(db, { type: q.type, limit: q.limit, offset: q.offset });
  });
}
