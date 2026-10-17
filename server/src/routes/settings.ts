import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import {
  getBotSettings,
  getStaffChatId,
  getStudioSettings,
  saveBotSettings,
  saveStudioSettings,
} from '../domain/settings.js';
import { badRequest } from '../lib/errors.js';
import { formatTimeOfDay, isValidTimezone, parseTimeOfDay } from '../lib/time.js';
import { nonNull, parse } from '../lib/validation.js';

const text = (max: number) =>
  z
    .string()
    .max(max)
    .nullish()
    .transform((v) => (v == null ? v : v.trim()));

/** "HH:MM" in the studio timezone, normalized to two-digit hours ("9:00" → "09:00"). */
const timeOfDay = z.string().transform((value, ctx) => {
  const minutes = parseTimeOfDay(value);
  if (minutes === null) {
    ctx.addIssue({ code: 'custom', message: 'время должно быть в формате ЧЧ:ММ (например, 10:00)' });
    return z.NEVER;
  }
  return formatTimeOfDay(minutes);
});

const studioBody = z.object({
  name: nonNull(z.string().trim().min(1).max(200)),
  address: text(500),
  phone: text(100),
  workingHours: text(500),
  instagram: text(200),
  website: text(300),
  about: text(5000),
  timezone: nonNull(z.string().trim().refine(isValidTimezone, { message: 'неизвестный часовой пояс (пример: Europe/Moscow)' })),
  workdayStart: nonNull(timeOfDay),
  workdayEnd: nonNull(timeOfDay),
});

const botBody = z.object({
  enabled: nonNull(z.boolean()),
  aiEnabled: nonNull(z.boolean()),
  greeting: nonNull(z.string().trim().min(1).max(2000)),
  extraInstructions: text(5000),
  aftercareHour: nonNull(z.number().int().min(0).max(23)),
  remindersEnabled: nonNull(z.boolean()),
  reminderHoursBefore: nonNull(z.number().int().min(1).max(168)),
});

export function botSettingsOut(ctx: AppContext) {
  return {
    ...getBotSettings(ctx.db),
    botUsername: ctx.gateway.username(),
    staffChatBound: getStaffChatId(ctx.db) !== null,
    aiConfigured: ctx.ai !== null,
  };
}

/** Merges a body into current values; `undefined` keeps the current value, `null` clears text. */
function merge<T extends object>(current: T, patch: Partial<Record<keyof T, unknown>>): T {
  const next = { ...current } as Record<string, unknown>;
  for (const [key, value] of Object.entries(patch)) {
    if (value === undefined) continue;
    next[key] = value === null ? '' : value;
  }
  return next as T;
}

export function settingsRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;

  app.get('/settings/studio', async () => getStudioSettings(db));

  app.put('/settings/studio', async (request) => {
    const input = parse(studioBody, request.body);
    const next = merge(getStudioSettings(db), input);
    // Only the calendar's default range: appointments outside it are still allowed.
    if (parseTimeOfDay(next.workdayEnd)! <= parseTimeOfDay(next.workdayStart)!) {
      throw badRequest(`Конец рабочего дня (${next.workdayEnd}) должен быть позже начала (${next.workdayStart})`);
    }
    return saveStudioSettings(db, next);
  });

  app.get('/settings/bot', async () => botSettingsOut(ctx));

  app.put('/settings/bot', async (request) => {
    const input = parse(botBody, request.body);
    const before = getBotSettings(db);
    const after = saveBotSettings(db, merge(before, input));
    if (before.enabled !== after.enabled) ctx.onBotSettingsChanged();
    return botSettingsOut(ctx);
  });
}
