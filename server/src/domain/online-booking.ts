import { randomBytes } from 'node:crypto';
import { and, count, eq, inArray } from 'drizzle-orm';
import type { AppContext } from '../context.js';
import type { DbOrTx } from '../db/client.js';
import { appointments, qrPayments, sales } from '../db/schema.js';
import { AppError, badRequest, conflict, errorMessage, scheduleConflict } from '../lib/errors.js';
import type { AppointmentRow, ClientRow, QrPaymentRow } from '../lib/serialize.js';
import { pluralWord } from '../lib/text.js';
import { localDate, MINUTE_MS } from '../lib/time.js';
import type { CreatedQr } from '../payments/qr-provider.js';
import { createAppointment } from './appointments.js';
import { chatEmployee, findChat } from './bot-chats.js';
import { createClient, findClientByChat, findClientByPhone, linkTelegram } from './clients.js';
import { forbidden } from './permissions.js';
import { auditOnlineBooked } from './online-booking-audit.js';
import { resolveItems, type BookingItem, type ResolvedItems } from './online-booking-items.js';
import { announceBooking } from './online-booking-messages.js';
import { assertOnlineMaster, bookingDates, chooseMaster, freeStart } from './online-booking-slots.js';
import { registerBankCode } from './qr-payments.js';
import { getClientRow } from './refs.js';
import { getStudioSettings, type OnlineBookingSettings } from './settings.js';

/**
 * The online booking engine shared by every channel (docs/API.md «Online booking»): the AI in Telegram (`bot`), the
 * Telegram Mini App (`miniapp`) and the booking page (`web`). A booking holds its time at once: with a prepayment
 * (and QR payments configured) it waits `holdMinutes` for the client to pay by QR, otherwise for staff to confirm it.
 * What happens next lives in online-booking-lifecycle.ts.
 */

export const ONLINE_CHANNELS = ['bot', 'miniapp', 'web'] as const;
export type OnlineChannel = (typeof ONLINE_CHANNELS)[number];
export const ONLINE_STATES = ['awaiting_payment', 'awaiting_confirmation'] as const;
export type OnlineState = (typeof ONLINE_STATES)[number];

/** Unsettled online bookings one client may have at once. */
export const MAX_UNSETTLED_PER_CLIENT = 2;
export const ONLINE_DISABLED = 'Онлайн-запись временно недоступна';
export const SLOT_TAKEN = 'Это время только что заняли — выберите другое';
export const TOO_MANY_UNSETTLED = 'У вас уже есть записи, которые ждут подтверждения — дождитесь ответа студии';
/** Where a card created by online booking says it came from. */
const CLIENT_SOURCES: Record<OnlineChannel, string> = { bot: 'telegram', miniapp: 'telegram', web: 'онлайн-запись' };
const OPEN_STATUSES = ['scheduled', 'confirmed'];

export interface OnlineBookingInput {
  channel: OnlineChannel;
  items: BookingItem[];
  /** A master, else «any». */
  masterId?: number | null;
  startsAt: number;
  comment?: string | null;
  /** The client known from the chat (the bot, a linked Mini App chat)… */
  clientId?: number | null;
  /** …else by phone (normalized): the card with it, or a new one with this name. */
  name?: string | null;
  phone?: string | null;
  /** The Mini App chat (the Telegram user id): told about the booking, linked to a new card. */
  chatId?: number | null;
  username?: string | null;
  now?: number;
}

export interface OnlineBookingResult {
  appointment: AppointmentRow;
  /** The prepayment code while the booking waits for the payment. */
  payment: QrPaymentRow | null;
  client: ClientRow;
}

/** What a booking would be, validated without writing (also the bot's test mode). */
export interface BookingCheck {
  items: ResolvedItems;
  startsAt: number;
  endsAt: number;
  /** Masters free at that start (only the chosen one when a master was asked for). */
  masterIds: number[];
  /** The booking will wait for the prepayment (else for staff). */
  prepayment: boolean;
}

/** `403` «Онлайн-запись временно недоступна» while staff have it off. */
export function assertOnlineEnabled(db: DbOrTx): OnlineBookingSettings {
  const settings = getStudioSettings(db).onlineBooking;
  if (!settings.enabled) throw forbidden(ONLINE_DISABLED);
  return settings;
}

export const newPublicToken = (): string => randomBytes(18).toString('base64url');
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{16,64}$/;

export function findBookingByToken(db: DbOrTx, token: string): AppointmentRow | null {
  if (!TOKEN_PATTERN.test(token)) return null;
  return db.select().from(appointments).where(eq(appointments.publicToken, token)).get() ?? null;
}

/** Online bookings of the client still waiting for a payment or for staff. */
export function unsettledCount(db: DbOrTx, clientId: number): number {
  return (
    db
      .select({ n: count() })
      .from(appointments)
      .where(
        and(
          eq(appointments.clientId, clientId),
          inArray(appointments.onlineState, [...ONLINE_STATES]),
          inArray(appointments.status, OPEN_STATUSES),
        ),
      )
      .get()?.n ?? 0
  );
}

/**
 * Whether a booking's link (`/start b_<token>`) or the Mini App may link a Telegram chat to this card. Anyone may type
 * any phone, so only a card without Telegram and without studio history (appointments made by staff, purchases) is
 * linked this way; anyone else shares the phone in the bot.
 */
export function mayLinkByBooking(db: DbOrTx, client: ClientRow): boolean {
  if (client.telegramChatId != null) return false;
  const staffMade = db.select({ n: count() }).from(appointments).where(and(eq(appointments.clientId, client.id), eq(appointments.channel, 'app'))).get();
  const bought = db.select({ n: count() }).from(sales).where(eq(sales.clientId, client.id)).get();
  return (staffMade?.n ?? 0) === 0 && (bought?.n ?? 0) === 0;
}

function assertBookableTime(db: DbOrTx, startsAt: number, now: number, settings: OnlineBookingSettings): void {
  if (startsAt < now + settings.leadMinutes * MINUTE_MS) {
    throw badRequest('Это время уже недоступно для онлайн-записи — выберите время попозже');
  }
  if (localDate(startsAt, getStudioSettings(db).timezone) > bookingDates(db, now).last) {
    const days = `${settings.horizonDays} ${pluralWord(settings.horizonDays, 'день', 'дня', 'дней')}`;
    throw badRequest(`Онлайн-запись открыта на ${days} вперёд — выберите дату пораньше`);
  }
}

/** Services, master and time: `400` / `403` / `409` with the reason, nothing written. */
export function checkOnlineBooking(ctx: AppContext, input: Omit<OnlineBookingInput, 'channel'>): BookingCheck {
  const { db } = ctx;
  const settings = assertOnlineEnabled(db);
  const now = input.now ?? Date.now();
  const items = resolveItems(db, input.items);
  if (input.masterId != null) assertOnlineMaster(db, input.masterId);
  assertBookableTime(db, input.startsAt, now, settings);
  const option = freeStart(db, { startsAt: input.startsAt, durationMin: items.durationMin, masterId: input.masterId, now });
  if (!option) throw scheduleConflict(SLOT_TAKEN);
  return {
    items,
    startsAt: input.startsAt,
    endsAt: input.startsAt + items.durationMin * MINUTE_MS,
    masterIds: option.masterIds,
    prepayment: items.depositRequired > 0 && ctx.qr !== null,
  };
}

/** The client of a booking that is about to be written: by chat, else by phone (null = a new card). */
function existingClient(db: DbOrTx, input: OnlineBookingInput): ClientRow | null {
  if (input.clientId != null) return getClientRow(db, input.clientId);
  if (!input.name?.trim()) throw badRequest('«Имя»: обязательное поле');
  if (!input.phone) throw badRequest('«Телефон»: обязательное поле');
  return findClientByPhone(db, input.phone);
}

/** A one-off prepayment code valid while the time is held; a bank failure leaves the booking for staff to confirm. */
async function registerHoldCode(ctx: AppContext, amount: number, holdMinutes: number): Promise<CreatedQr | null> {
  try {
    const purpose = `Предоплата, ${getStudioSettings(ctx.db).name}`.slice(0, 140);
    return await registerBankCode(ctx, ctx.qr!, { amount, purpose, ttlMinutes: holdMinutes });
  } catch (err) {
    ctx.log.error({ err: errorMessage(err) }, 'online booking: no prepayment code, the booking waits for staff');
    return null;
  }
}

/** The Mini App chat becomes the client's when it has no client yet and the card may be linked this way. */
function linkMiniAppChat(db: DbOrTx, input: OnlineBookingInput, client: ClientRow, created: boolean): void {
  const chatId = input.chatId!;
  if (findClientByChat(db, chatId) || chatEmployee(db, findChat(db, chatId))) return;
  if (!created && !mayLinkByBooking(db, client)) return;
  linkTelegram(db, client.id, chatId, input.username ?? null);
}

/** Writes the booking in one transaction, checking the time and the limit again (the bank call took a while). */
function commit(ctx: AppContext, input: OnlineBookingInput, check: BookingCheck, code: CreatedQr | null, started: number): OnlineBookingResult {
  const { db } = ctx;
  const { holdMinutes } = getStudioSettings(db).onlineBooking;
  return db.transaction((tx) => {
    const now = Date.now();
    const option = freeStart(tx, { startsAt: input.startsAt, durationMin: check.items.durationMin, masterId: input.masterId, now });
    if (!option) throw scheduleConflict(SLOT_TAKEN);
    const masterId = input.masterId ?? chooseMaster(tx, input.startsAt, option.masterIds);
    const existing = existingClient(tx, input);
    const client = existing ?? createClient(tx, { name: input.name!.trim(), phone: input.phone!, source: CLIENT_SOURCES[input.channel] });
    if (unsettledCount(tx, client.id) >= MAX_UNSETTLED_PER_CLIENT) throw conflict(TOO_MANY_UNSETTLED);
    let created: AppointmentRow;
    try {
      created = createAppointment(tx, {
        clientId: client.id,
        masterId,
        services: check.items.lines,
        startsAt: input.startsAt,
        endsAt: check.endsAt,
        price: check.items.price,
        depositRequired: check.items.depositRequired,
        notes: input.comment?.trim() || null,
        status: 'scheduled',
      });
    } catch (err) {
      // Never pass on the regular overlap message: it names another client.
      if (err instanceof AppError && err.code === 'schedule_conflict') throw scheduleConflict(SLOT_TAKEN);
      throw err;
    }
    const holdUntil = code ? started + holdMinutes * MINUTE_MS : null;
    const appointment = tx
      .update(appointments)
      .set({
        channel: input.channel,
        onlineState: code ? 'awaiting_payment' : 'awaiting_confirmation',
        holdUntil,
        publicToken: newPublicToken(),
        updatedAt: now,
      })
      .where(eq(appointments.id, created.id))
      .returning()
      .get()!;
    const payment = code
      ? tx
          .insert(qrPayments)
          .values({
            kind: 'deposit',
            appointmentId: appointment.id,
            provider: ctx.qr!.name,
            externalId: code.externalId,
            payload: code.payload,
            amount: check.items.depositRequired,
            status: 'pending',
            saleInputJson: null,
            // No employee issued it: the code is the booked master's (the column is required).
            employeeId: masterId,
            expiresAt: holdUntil!,
            createdAt: now,
            updatedAt: now,
          })
          .returning()
          .get()
      : null;
    if (input.chatId != null) linkMiniAppChat(tx, input, client, existing === null);
    return { appointment, payment, client: getClientRow(tx, client.id) };
  });
}

/**
 * Books online: validates, registers the prepayment code when one is due, writes the booking, logs it and tells the
 * staff chat and the client (the bot's AI tells its client itself — see bot/booking-tool.ts).
 */
export async function createOnlineBooking(ctx: AppContext, input: OnlineBookingInput): Promise<OnlineBookingResult> {
  const check = checkOnlineBooking(ctx, input);
  const known = existingClient(ctx.db, input);
  if (known && unsettledCount(ctx.db, known.id) >= MAX_UNSETTLED_PER_CLIENT) throw conflict(TOO_MANY_UNSETTLED);
  const started = Date.now();
  const holdMinutes = getStudioSettings(ctx.db).onlineBooking.holdMinutes;
  const code = check.prepayment ? await registerHoldCode(ctx, check.items.depositRequired, holdMinutes) : null;
  const result = commit(ctx, input, check, code, started);
  auditOnlineBooked(ctx, result.appointment);
  await announceBooking(ctx, result.appointment, result.payment, {
    toClient: input.channel !== 'bot',
    chatId: input.channel === 'miniapp' ? input.chatId : null,
  });
  return result;
}
