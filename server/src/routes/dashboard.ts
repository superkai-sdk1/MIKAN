import { and, count, eq, gte, lt, sql } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { sales } from '../db/schema.js';
import { listAppointments } from '../domain/appointments.js';
import { getOpenShift, serializeShift } from '../domain/cash.js';
import { serializeAppointments } from '../domain/refs.js';
import { badges, reportSummary } from '../domain/reports.js';
import { studioTimezone } from '../domain/settings.js';
import { badRequest } from '../lib/errors.js';
import { DAY_MS, localDayBounds } from '../lib/time.js';
import { instant, parse } from '../lib/validation.js';

const MAX_REPORT_DAYS = 400;
const reportQuery = z.object({ from: instant, to: instant });

export function dashboardRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;

  app.get('/badges', async () => badges(db));

  app.get('/dashboard', async () => {
    const tz = studioTimezone(db);
    const day = localDayBounds(Date.now(), tz);
    const todays = listAppointments(db, {
      from: day.start,
      to: day.end,
      statuses: ['scheduled', 'confirmed', 'completed', 'no_show'],
    });
    const salesToday = db
      .select({ n: count(), revenue: sql<number>`coalesce(sum(${sales.total}), 0)` })
      .from(sales)
      .where(and(eq(sales.status, 'completed'), gte(sales.createdAt, day.start), lt(sales.createdAt, day.end)))
      .get();
    const open = getOpenShift(db);
    return {
      date: day.date,
      appointments: serializeAppointments(db, todays),
      revenueToday: salesToday?.revenue ?? 0,
      salesCountToday: salesToday?.n ?? 0,
      openShift: open ? serializeShift(db, open, true) : null,
      badges: badges(db),
    };
  });

  app.get('/reports/summary', async (request) => {
    const q = parse(reportQuery, request.query);
    if (q.to <= q.from) throw badRequest('Конец периода должен быть позже начала');
    if (q.to - q.from > MAX_REPORT_DAYS * DAY_MS) throw badRequest(`Период отчёта — не больше ${MAX_REPORT_DAYS} дней`);
    return reportSummary(db, q.from, q.to);
  });
}
