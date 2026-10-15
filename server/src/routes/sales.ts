import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { getSaleRow, serializeSale } from '../domain/refs.js';
import { createSale, listSales, refundSale, type SaleInput } from '../domain/sales.js';
import { badRequest } from '../lib/errors.js';
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
export const saleBody = z.object({
  clientId: id.nullish(),
  appointmentId: id.nullish(),
  items: z.array(item).min(1).max(100),
  discount: nonNull(money),
  payments: z.object({ cash: nonNull(money), card: nonNull(money), transfer: nonNull(money), qr: nonNull(money) }),
  note: nullableText(1000),
});
export type SaleBody = z.infer<typeof saleBody>;

/** Fills the optional parts of a validated body. */
export function saleInputOf(input: SaleBody): SaleInput {
  return {
    clientId: input.clientId,
    appointmentId: input.appointmentId,
    items: input.items.map((i) => ({ ...i, quantity: i.quantity ?? 1 })),
    discount: input.discount ?? 0,
    payments: {
      cash: input.payments.cash ?? 0,
      card: input.payments.card ?? 0,
      transfer: input.payments.transfer ?? 0,
      qr: input.payments.qr ?? 0,
    },
    note: input.note,
  };
}

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
    const input = saleInputOf(parse(saleBody, request.body));
    // QR money is only counted once the bank confirms it: such a sale is created by POST /qr-payments.
    if (input.payments.qr > 0) throw badRequest('Оплату по QR-коду проводите через «Показать QR-код»');
    return idempotent(db, request, reply, (tx) => serializeSale(tx, createSale(tx, input, request.employee.id)));
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
