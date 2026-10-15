import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { DEPOSIT_DELIVERIES, issueDepositCode, remindDeposit, type DepositLinkResult } from '../domain/deposit-links.js';
import { DEPOSIT_METHODS } from '../domain/deposit-ledger.js';
import { MANUAL_DEPOSIT_METHODS, receiveDeposit, refundDeposit, retainDeposit } from '../domain/deposits.js';
import { serializeQrPayment } from '../domain/qr-payments.js';
import { serializeAppointment } from '../domain/refs.js';
import type { DbOrTx } from '../db/client.js';
import { idempotent } from '../lib/idempotency.js';
import { idParams, money, nonNull, nullableText, parse } from '../lib/validation.js';

const positiveMoney = money.refine((v) => v > 0, { message: 'должно быть больше 0' });
const chatId = z.number().int().nullish();

const receiveBody = z.object({ amount: positiveMoney, method: z.enum(MANUAL_DEPOSIT_METHODS), note: nullableText(500) });
const refundBody = z.object({
  amount: nonNull(positiveMoney),
  method: nonNull(z.enum(DEPOSIT_METHODS)),
  reason: nullableText(500),
});
const retainBody = z.object({ amount: nonNull(positiveMoney), reason: nullableText(500) });
const qrBody = z.object({ delivery: z.enum(DEPOSIT_DELIVERIES), amount: nonNull(positiveMoney), chatId });
const remindBody = z.object({ chatId });

/** Bank requests and Telegram messages: limited like `POST /qr-payments`. */
const linkLimit = { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } };

function linkResultOut(db: DbOrTx, result: DepositLinkResult) {
  return {
    appointment: serializeAppointment(db, result.appointment),
    payment: serializeQrPayment(db, result.payment),
    sendError: result.sendError,
  };
}

/** Prepayments of an appointment (see «Prepayments» in docs/API.md). */
export function depositRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;

  app.post('/appointments/:id/deposit', async (request, reply) => {
    const { id } = parse(idParams, request.params);
    const input = parse(receiveBody, request.body);
    return idempotent(db, request, reply, (tx) => serializeAppointment(tx, receiveDeposit(tx, id, input, request.employee.id)));
  });

  app.post('/appointments/:id/deposit/refund', async (request, reply) => {
    const { id } = parse(idParams, request.params);
    const input = parse(refundBody, request.body);
    return idempotent(db, request, reply, (tx) => serializeAppointment(tx, refundDeposit(tx, id, input, request.employee.id)));
  });

  app.post('/appointments/:id/deposit/retain', async (request, reply) => {
    const { id } = parse(idParams, request.params);
    const input = parse(retainBody, request.body);
    return idempotent(db, request, reply, (tx) => serializeAppointment(tx, retainDeposit(tx, id, input, request.employee.id)));
  });

  app.post('/appointments/:id/deposit/qr', linkLimit, async (request) => {
    const { id } = parse(idParams, request.params);
    const input = parse(qrBody, request.body);
    return linkResultOut(db, await issueDepositCode(ctx, id, input, request.employee.id));
  });

  app.post('/appointments/:id/deposit/remind', linkLimit, async (request) => {
    const { id } = parse(idParams, request.params);
    const input = parse(remindBody, request.body);
    return linkResultOut(db, await remindDeposit(ctx, id, input, request.employee.id));
  });
}
