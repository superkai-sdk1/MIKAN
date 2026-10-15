import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import {
  addCashOperation,
  closeShift,
  getOpenShift,
  getShiftRow,
  listShifts,
  openShift,
  serializeShift,
} from '../domain/cash.js';
import { idempotent } from '../lib/idempotency.js';
import { cashOpOut, employeeRef } from '../lib/serialize.js';
import { idParams, money, nullableText, pagination, parse, requiredText } from '../lib/validation.js';

const openBody = z.object({ openingCash: money });
const closeBody = z.object({ closingCash: money, note: nullableText(1000) });
const operationBody = z.object({
  type: z.enum(['in', 'out']),
  amount: money.refine((v) => v > 0, { message: 'сумма должна быть больше 0' }),
  reason: requiredText(300),
});

export function cashRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;

  app.get('/cash/shift/current', async () => {
    const open = getOpenShift(db);
    return { shift: open ? serializeShift(db, open, true) : null };
  });

  app.post('/cash/shift/open', async (request) => {
    const input = parse(openBody, request.body);
    return serializeShift(db, openShift(db, input.openingCash, request.employee.id), true);
  });

  app.post('/cash/shift/close', async (request) => {
    const input = parse(closeBody, request.body);
    return serializeShift(db, closeShift(db, input, request.employee.id), true);
  });

  app.post('/cash/operations', async (request, reply) => {
    const input = parse(operationBody, request.body);
    return idempotent(db, request, reply, (tx) =>
      cashOpOut(addCashOperation(tx, input, request.employee.id), employeeRef(request.employee)),
    );
  });

  app.get('/cash/shifts', async (request) => {
    const q = parse(pagination, request.query);
    return listShifts(db, q.limit, q.offset);
  });

  app.get('/cash/shifts/:id', async (request) => {
    const params = parse(idParams, request.params);
    return serializeShift(db, getShiftRow(db, params.id), true);
  });
}
