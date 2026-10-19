import type { AppContext } from '../context.js';
import { chatEmployee, findChat, storeMessage } from '../domain/bot-chats.js';
import { findClientByChat, linkTelegram } from '../domain/clients.js';
import { findBookingByToken, mayLinkByBooking } from '../domain/online-booking.js';
import { BOOKING_WEB_APP_BUTTON, bookingWebAppUrl } from '../domain/online-booking-links.js';
import { bookingFacts } from '../domain/online-booking-messages.js';
import { bookingStatusText } from '../domain/online-booking-public.js';
import { getClientRow } from '../domain/refs.js';
import { getStudioSettings } from '../domain/settings.js';
import { errorMessage } from '../lib/errors.js';
import type { InlineKeyboard } from './gateway.js';
import type { IncomingFrom } from './pipeline.js';

/** Online booking in the bot's chat: `/start b_<token>` from a booking page, and the «Записаться онлайн» button. */

export const BOOKING_OFFER_TEXT = '📅 Записаться можно прямо здесь: выберите услугу, мастера и свободное время — это займёт минуту.';

/**
 * `/start b_<token>`: links the chat to the booking's client (when the chat has no client yet and the card may be
 * linked this way, see `mayLinkByBooking`) and answers with the booking's status; null for an unknown token.
 */
export function bookingStartText(ctx: AppContext, from: IncomingFrom, token: string): string | null {
  const { db } = ctx;
  const booking = findBookingByToken(db, token);
  if (!booking) return null;
  const client = getClientRow(db, booking.clientId);
  const own = findClientByChat(db, from.chatId);
  let linked = own?.id === client.id;
  if (!own && !chatEmployee(db, findChat(db, from.chatId)) && mayLinkByBooking(db, client)) {
    linkTelegram(db, client.id, from.chatId, from.username);
    linked = true;
  }
  const f = bookingFacts(db, booking);
  const details = `Запись №${booking.id}: ${f.when} — ${f.what}, мастер ${f.master}\nСтатус: ${bookingStatusText(db, booking)}`;
  return linked ? `${client.name}, нашёл вашу запись ✅\n\n${details}\n\nСюда придут уведомления о ней и напоминание перед визитом.` : details;
}

/** The Mini App button under the greeting of a client chat, while online booking is on and the page is `https://`. */
export function bookingOffer(ctx: AppContext, reply: { staff?: boolean }): { text: string; keyboard: InlineKeyboard } | null {
  if (reply.staff || !getStudioSettings(ctx.db).onlineBooking.enabled) return null;
  const url = bookingWebAppUrl(ctx.config);
  return url ? { text: BOOKING_OFFER_TEXT, keyboard: [[{ text: BOOKING_WEB_APP_BUTTON, webApp: url }]] } : null;
}

/** Sends the offer after the greeting; a failure is only logged. */
export async function sendBookingOffer(ctx: AppContext, chatId: number, reply: { staff?: boolean }): Promise<void> {
  const offer = bookingOffer(ctx, reply);
  if (!offer) return;
  try {
    await ctx.gateway.sendText(chatId, offer.text, { keyboard: offer.keyboard });
    storeMessage(ctx.db, chatId, 'system', offer.text);
  } catch (err) {
    ctx.log.warn({ chatId, err: errorMessage(err) }, 'online booking button not sent');
  }
}
