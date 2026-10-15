import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { getSaleRow, serializeSale } from '../domain/refs.js';
import { createSale, listSales, refundSale } from '../domain/sales.js';
import { idempotent } from '../lib/idempotency.js';
import { idParams, money, nonNull, nullableText, pagination, parse, queryId, queryInstant, requiredText } from '../lib/validation.js';

const id = z.number().int().positive();
const item = z.object({
  type: z.enum(['product', 'service']),
  productId: id.nullish(),
  serviceId: id.nullish(),
  name: nullableText(200),
  quantity: nonNull(z.number().int().min(1).max(10_000)),
  price: money.nullish(),
});
const createBody = z.object({
  clientId: id.nullish(),
  appointmentId: id.nullish(),
  items: z.array(item).min(1).max(100),
  discount: nonNull(money),
  payments: z.object({ cash: nonNull(money), card: nonNull(money), transfer: nonNull(money) }),
  note: nullableText(1000),
});
const refundBody = z.object({ reason: requiredText(500), restock: nonNull(z.boolean()) });
const listQuery = pagination.extend({ from: queryInstant, to: queryInstant, clientId: queryId });

export function salesRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;

  app.get('/sales', async (request) => {
    const q = parse(listQuery, request.query);
    return listSales(db, q);
  });

  app.get('/sales/:id', async (request) => {
    const params = parse(idParams, request.params);
    return serializeSale(db, getSaleRow(db, params.id));
  });

  app.post('/sales', async (request, reply) => {
    const input = parse(createBody, request.body);
    return idempotent(db, request, reply, (tx) => {
      const sale = createSale(
        tx,
        {
          clientId: input.clientId,
          appointmentId: input.appointmentId,
          items: input.items.map((i) => ({ ...i, quantity: i.quantity ?? 1 })),
          discount: input.discount ?? 0,
          payments: {
            cash: input.payments.cash ?? 0,
            card: input.payments.card ?? 0,
            transfer: input.payments.transfer ?? 0,
          },
          note: input.note,
        },
        request.employee.id,
      );
      return serializeSale(tx, sale);
    });
  });

  app.post('/sales/:id/refund', async (request, reply) => {
    const params = parse(idParams, request.params);
    const input = parse(refundBody, request.body);
    return idempotent(db, request, reply, (tx) => {
      const sale = refundSale(tx, params.id, { reason: input.reason, restock: input.restock ?? true }, request.employee.id);
      return serializeSale(tx, sale);
    });
  });
}
