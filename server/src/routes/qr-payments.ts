import type { FastifyInstance } from 'fastify';
import type { AppContext } from '../context.js';
import {
  cancelQrPayment,
  createQrPayment,
  refreshQrPayment,
  serializeQrPayment,
} from '../domain/qr-payments.js';
import { idParams, parse } from '../lib/validation.js';
import { saleBody, saleInputOf } from './sales.js';

export function qrPaymentRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;

  app.get('/qr-payments/config', async () => ({ enabled: ctx.qr !== null }));

  app.post('/qr-payments', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request) => {
    const input = saleInputOf(parse(saleBody, request.body));
    const row = await createQrPayment(ctx, input, request.employee.id);
    return serializeQrPayment(db, row);
  });

  // The app polls every ~2 s; the bank is asked at most once per code at a time.
  app.get('/qr-payments/:id', { config: { rateLimit: { max: 120, timeWindow: '1 minute' } } }, async (request) => {
    const { id } = parse(idParams, request.params);
    return serializeQrPayment(db, await refreshQrPayment(ctx, id));
  });

  app.post('/qr-payments/:id/cancel', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request) => {
    const { id } = parse(idParams, request.params);
    return serializeQrPayment(db, await cancelQrPayment(ctx, id));
  });
}
