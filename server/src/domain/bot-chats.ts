import { and, asc, desc, eq, inArray, lt, sql } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { botChats, botMessages, bookingRequests, clients, scheduledMessages } from '../db/schema.js';
import { notFound } from '../lib/errors.js';
import {
  bookingOut,
  botChatOut,
  botMessageOut,
  clientRef,
  scheduledOut,
  type BookingRow,
  type BotChatRow,
  type BotMessageRow,
  type ClientRow,
  type ScheduledRow,
} from '../lib/serialize.js';
import { clientsByIds, employeeRefOrMissing, employeesByIds } from './refs.js';

export type BotRole = 'user' | 'assistant' | 'staff' | 'system';

export function findChat(db: DbOrTx, chatId: number): BotChatRow | null {
  return db.select().from(botChats).where(eq(botChats.chatId, chatId)).get() ?? null;
}

export function getChat(db: DbOrTx, chatId: number): BotChatRow {
  const chat = findChat(db, chatId);
  if (!chat) throw notFound('Чат не найден');
  return chat;
}

/** The client's bot chat: the chat linked to the client first, else the latest chat attributed to the client. */
export function findClientChat(db: DbOrTx, client: ClientRow): BotChatRow | null {
  const linked = client.telegramChatId != null ? findChat(db, client.telegramChatId) : null;
  if (linked) return linked;
  return (
    db
      .select()
      .from(botChats)
      .where(eq(botChats.clientId, client.id))
      .orderBy(desc(botChats.updatedAt), desc(botChats.chatId))
      .get() ?? null
  );
}

/** Creates the chat row if missing and refreshes the Telegram display name / username. */
export function upsertChat(
  db: DbOrTx,
  chatId: number,
  info: { telegramName?: string | null; username?: string | null; clientId?: number | null } = {},
): BotChatRow {
  const now = Date.now();
  const existing = findChat(db, chatId);
  const linkedClient = db.select({ id: clients.id }).from(clients).where(eq(clients.telegramChatId, chatId)).get();
  if (!existing) {
    return db
      .insert(botChats)
      .values({
        chatId,
        clientId: info.clientId ?? linkedClient?.id ?? null,
        telegramName: info.telegramName ?? null,
        username: info.username ?? null,
        createdAt: now,
        updatedAt: now,
      })
      .returning()
      .get();
  }
  return db
    .update(botChats)
    .set({
      telegramName: info.telegramName ?? existing.telegramName,
      username: info.username ?? existing.username,
      clientId: info.clientId ?? linkedClient?.id ?? existing.clientId,
    })
    .where(eq(botChats.chatId, chatId))
    .returning()
    .get();
}

export function storeMessage(
  db: DbOrTx,
  chatId: number,
  role: BotRole,
  text: string,
  opts: { employeeId?: number | null; bumpUnread?: boolean } = {},
): BotMessageRow {
  const now = Date.now();
  if (!findChat(db, chatId)) upsertChat(db, chatId);
  const message = db
    .insert(botMessages)
    .values({ chatId, role, text, employeeId: opts.employeeId ?? null, createdAt: now })
    .returning()
    .get();
  db.update(botChats)
    .set({
      updatedAt: now,
      ...(opts.bumpUnread ? { unreadCount: sql`${botChats.unreadCount} + 1` } : {}),
    })
    .where(eq(botChats.chatId, chatId))
    .run();
  return message;
}

export function updateChatFlags(
  db: DbOrTx,
  chatId: number,
  patch: { needsAttention?: boolean; aiPaused?: boolean; unreadCount?: number },
): BotChatRow {
  getChat(db, chatId);
  return db.update(botChats).set(patch).where(eq(botChats.chatId, chatId)).returning().get();
}

export function serializeMessages(db: DbOrTx, rows: BotMessageRow[]) {
  const emps = employeesByIds(db, rows.map((r) => r.employeeId));
  return rows.map((m) => botMessageOut(m, employeeRefOrMissing(emps, m.employeeId)));
}

export function serializeChats(db: DbOrTx, rows: BotChatRow[]) {
  if (rows.length === 0) return [];
  const lastIds = db
    .select({ chatId: botMessages.chatId, id: sql<number>`max(${botMessages.id})` })
    .from(botMessages)
    .where(inArray(botMessages.chatId, rows.map((r) => r.chatId)))
    .groupBy(botMessages.chatId)
    .all();
  const lastRows = lastIds.length
    ? db.select().from(botMessages).where(inArray(botMessages.id, lastIds.map((l) => l.id))).all()
    : [];
  const lastByChat = new Map(serializeMessages(db, lastRows).map((m) => [m.chatId, m]));
  const cl = clientsByIds(db, rows.map((r) => r.clientId));
  return rows.map((chat) => {
    const client = chat.clientId != null ? cl.get(chat.clientId) : undefined;
    return botChatOut(chat, client ? clientRef(client) : null, lastByChat.get(chat.chatId) ?? null);
  });
}

export function serializeChat(db: DbOrTx, row: BotChatRow) {
  return serializeChats(db, [row])[0]!;
}

export function listChats(db: DbOrTx) {
  return serializeChats(db, db.select().from(botChats).orderBy(desc(botChats.updatedAt), desc(botChats.chatId)).all());
}

/** The page of messages before `beforeId` (or the latest page), returned in ascending order. */
export function pageMessages(db: DbOrTx, chatId: number, beforeId: number | undefined, limit: number): BotMessageRow[] {
  const conditions = [eq(botMessages.chatId, chatId)];
  if (beforeId !== undefined) conditions.push(lt(botMessages.id, beforeId));
  return db
    .select()
    .from(botMessages)
    .where(and(...conditions))
    .orderBy(desc(botMessages.id))
    .limit(limit)
    .all()
    .reverse();
}

export function serializeScheduled(db: DbOrTx, rows: ScheduledRow[]) {
  const cl = clientsByIds(db, rows.map((r) => r.clientId));
  return rows.map((m) => {
    const c = cl.get(m.clientId);
    return scheduledOut(m, c ? clientRef(c) : { id: m.clientId, name: 'Удалённый клиент', phone: null, telegramLinked: false });
  });
}

export function listScheduled(db: DbOrTx, status: string | undefined) {
  const rows = db
    .select()
    .from(scheduledMessages)
    .where(status ? eq(scheduledMessages.status, status) : undefined)
    .orderBy(asc(scheduledMessages.sendAt), asc(scheduledMessages.id))
    .all();
  return serializeScheduled(db, rows);
}

export function serializeBookings(db: DbOrTx, rows: BookingRow[]) {
  const cl = clientsByIds(db, rows.map((r) => r.clientId));
  return rows.map((b) => {
    const c = b.clientId != null ? cl.get(b.clientId) : undefined;
    return bookingOut(b, c ? clientRef(c) : null);
  });
}

export function listBookings(db: DbOrTx, status: string | undefined) {
  const rows = db
    .select()
    .from(bookingRequests)
    .where(status ? eq(bookingRequests.status, status) : undefined)
    .orderBy(desc(bookingRequests.createdAt), desc(bookingRequests.id))
    .all();
  return serializeBookings(db, rows);
}
