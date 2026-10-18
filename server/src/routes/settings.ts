import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { resyncUpcomingReminders } from '../domain/scheduling.js';
import {
  getBotSettings,
  getStaffChatId,
  getStudioSettings,
  LEGACY_REMINDER_HOURS_MAX,
  legacyReminderHours,
  MAX_REMINDER_OFFSETS,
  normalizeReminderOffsets,
  REMINDER_OFFSET_MAX,
  REMINDER_OFFSET_MIN,
  saveBotSettings,
  saveStudioSettings,
  type BotSettingsStored,
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
  reminderOffsets: nonNull(
    z
      .array(z.number().int().min(REMINDER_OFFSET_MIN).max(REMINDER_OFFSET_MAX))
      .min(1)
      .max(MAX_REMINDER_OFFSETS)
      .refine((list) => new Set(list).size === list.length, { message: 'напоминания не должны повторяться' }),
  ),
  /** Older builds: a single reminder N hours before. */
  reminderHoursBefore: nonNull(z.number().int().min(1).max(LEGACY_REMINDER_HOURS_MAX)),
  /** Omitted = unchanged, `null` = that digest is off. */
  morningDigestAt: timeOfDay.nullish(),
  eveningDigestAt: timeOfDay.nullish(),
});

export function botSettingsOut(ctx: AppContext) {
  const bot = getBotSettings(ctx.db);
  return {
    ...bot,
    reminderHoursBefore: legacyReminderHours(bot.reminderOffsets),
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

/**
 * `reminderHoursBefore` from older builds: a single reminder N hours before. Those builds resend the value they
 * read, so an unchanged value keeps the current (possibly several) reminders.
 */
function legacyOffsets(current: BotSettingsStored, hours: number | undefined): number[] | undefined {
  if (hours === undefined || hours === legacyReminderHours(current.reminderOffsets)) return undefined;
  return [hours * 60];
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
    const { reminderHoursBefore, reminderOffsets, morningDigestAt, eveningDigestAt, ...input } = parse(botBody, request.body);
    const before = getBotSettings(db);
    const offsets = reminderOffsets ?? legacyOffsets(before, reminderHoursBefore);
    const after = saveBotSettings(db, {
      ...merge(before, input),
      reminderOffsets: offsets ? normalizeReminderOffsets(offsets) : before.reminderOffsets,
      // `merge` turns null into '' (text fields); here null means «off».
      morningDigestAt: morningDigestAt === undefined ? before.morningDigestAt : morningDigestAt,
      eveningDigestAt: eveningDigestAt === undefined ? before.eveningDigestAt : eveningDigestAt,
    });
    if (before.enabled !== after.enabled) ctx.onBotSettingsChanged();
    const remindersChanged =
      before.remindersEnabled !== after.remindersEnabled || before.reminderOffsets.join() !== after.reminderOffsets.join();
    if (remindersChanged) resyncUpcomingReminders(db);
    return botSettingsOut(ctx);
  });
}
