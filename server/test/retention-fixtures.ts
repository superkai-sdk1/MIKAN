import { eq } from 'drizzle-orm';
import { DateTime } from 'luxon';
import { appointments, appointmentServices, bonusOperations, clients } from '../src/db/schema.js';
import { linkTelegram } from '../src/domain/clients.js';
import type { Clock } from '../src/lib/pacer.js';
import { make, type TestApp } from './helpers.js';

/** Fixtures of the retention tests (campaigns, birthday and win-back): clients, visits, bonuses and a fake clock. */

export const DAY = 86_400_000;
export const TZ = 'Europe/Moscow';

/** `months` calendar months before `now` (studio time), plus `days`. */
export const monthsBefore = (now: number, months: number, days = 0): number =>
  DateTime.fromMillis(now, { zone: TZ }).minus({ months, days }).toMillis();

let nextPhone = 1000;

export interface ClientOptions {
  lastName?: string;
  /** Telegram chat id to link; omitted = not linked. */
  chatId?: number;
  birthday?: string;
  botEnabled?: boolean;
  marketingOptOut?: boolean;
  archived?: boolean;
  createdAt?: number;
}

export async function addClient(t: TestApp, name: string, options: ClientOptions = {}): Promise<{ id: number; name: string }> {
  nextPhone += 1;
  const client = await make(t, '/api/clients', {
    name,
    phone: `+7999000${String(nextPhone).padStart(4, '0')}`,
    ...(options.lastName ? { lastName: options.lastName } : {}),
    ...(options.birthday ? { birthday: options.birthday } : {}),
  });
  if (options.chatId !== undefined) linkTelegram(t.ctx.db, client.id, options.chatId, null);
  const patch = {
    ...(options.botEnabled !== undefined ? { botEnabled: options.botEnabled } : {}),
    ...(options.marketingOptOut !== undefined ? { marketingOptOut: options.marketingOptOut } : {}),
    ...(options.archived !== undefined ? { archived: options.archived } : {}),
    ...(options.createdAt !== undefined ? { createdAt: options.createdAt } : {}),
  };
  if (Object.keys(patch).length) t.ctx.db.update(clients).set(patch).where(eq(clients.id, client.id)).run();
  return client;
}

export interface VisitOptions {
  at: number;
  masterId?: number;
  serviceIds?: number[];
  status?: string;
}

/** An appointment written straight to the database (any time, any status), with its service lines. */
export function addVisit(t: TestApp, clientId: number, options: VisitOptions): number {
  const { db } = t.ctx;
  const row = db
    .insert(appointments)
    .values({
      clientId,
      masterId: options.masterId ?? 1,
      startsAt: options.at,
      endsAt: options.at + 3_600_000,
      status: options.status ?? 'completed',
      price: 1000,
      completedAt: (options.status ?? 'completed') === 'completed' ? options.at + 3_600_000 : null,
      createdAt: options.at,
      updatedAt: options.at,
    })
    .returning()
    .get();
  (options.serviceIds ?? []).forEach((serviceId, position) => {
    db.insert(appointmentServices).values({ appointmentId: row.id, serviceId, name: `Услуга ${serviceId}`, price: 1000, durationMin: 60, position }).run();
  });
  return row.id;
}

export function addBonusLot(t: TestApp, clientId: number, remaining: number, expiresAt: number | null): void {
  t.ctx.db
    .insert(bonusOperations)
    .values({ clientId, type: 'gift', amount: remaining, remaining, expiresAt, note: 'тест', createdAt: Date.now() })
    .run();
}

/** A clock whose sleep moves time forward at once. */
export class FakeClock implements Clock {
  constructor(public t: number) {}
  now(): number {
    return this.t;
  }
  async sleep(ms: number): Promise<void> {
    this.t += ms;
  }
}
