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
import { isValidTimezone } from '../lib/time.js';
import { nonNull, parse } from '../lib/validation.js';

const text = (max: number) =>
  z
    .string()
    .max(max)
    .nullish()
    .transform((v) => (v == null ? v : v.trim()));

const studioBody = z.object({
  name: nonNull(z.string().trim().min(1).max(200)),
  address: text(500),
  phone: text(100),
  workingHours: text(500),
  instagram: text(200),
  website: text(300),
  about: text(5000),
  timezone: nonNull(z.string().trim().refine(isValidTimezone, { message: 'неизвестный часовой пояс (пример: Europe/Moscow)' })),
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
    return saveStudioSettings(db, merge(getStudioSettings(db), input));
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
