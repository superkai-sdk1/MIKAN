import { and, asc, eq, inArray } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { waitlistEntries } from '../db/schema.js';
import { conflict, notFound } from '../lib/errors.js';
import { employeeRef, type EmployeeRef } from '../lib/serialize.js';
import { toIso } from '../lib/time.js';
import { employeesByIds, servicesByIds } from './refs.js';

/**
 * The client's waitlist entries in the cabinet (docs/API.md «Waitlist», `WaitlistEntryPublic`): the ones still
 * waiting or already told about a free time, and cancelling them.
 */

type WaitlistRow = typeof waitlistEntries.$inferSelect;

/** Entries the client can still cancel. */
export const OPEN_WAITLIST_STATUSES = ['waiting', 'notified'];

export interface WaitlistEntryPublic {
  id: number;
  items: Array<{ serviceId: number; variant: string | null; name: string }>;
  master: EmployeeRef | null;
  dateFrom: string;
  dateTo: string;
  status: string;
  channel: string;
  notifiedAt: string | null;
  appointmentId: number | null;
  note: string | null;
  createdAt: string;
}

/** `[{ serviceId, variant? }]` of the stored JSON; anything malformed is skipped. */
function parseItems(json: string): Array<{ serviceId: number; variant: string | null }> {
  try {
    const value: unknown = JSON.parse(json);
    if (!Array.isArray(value)) return [];
    return value.flatMap((item) => {
      const v = item as { serviceId?: unknown; variant?: unknown } | null;
      if (typeof v?.serviceId !== 'number') return [];
      return [{ serviceId: v.serviceId, variant: typeof v.variant === 'string' && v.variant.trim() ? v.variant.trim() : null }];
    });
  } catch {
    return [];
  }
}

export function waitlistEntriesPublic(db: DbOrTx, rows: WaitlistRow[]): WaitlistEntryPublic[] {
  const items = new Map(rows.map((r) => [r.id, parseItems(r.items)]));
  const services = servicesByIds(db, [...items.values()].flat().map((i) => i.serviceId));
  const masters = employeesByIds(db, rows.map((r) => r.masterId));
  return rows.map((r) => {
    const master = r.masterId != null ? masters.get(r.masterId) : undefined;
    return {
      id: r.id,
      items: (items.get(r.id) ?? []).map((i) => {
        const name = services.get(i.serviceId)?.name ?? 'Услуга';
        return { serviceId: i.serviceId, variant: i.variant, name: i.variant ? `${name} — ${i.variant}` : name };
      }),
      master: master ? employeeRef(master) : null,
      dateFrom: r.dateFrom,
      dateTo: r.dateTo,
      status: r.status,
      channel: r.channel,
      notifiedAt: toIso(r.notifiedAt),
      appointmentId: r.appointmentId,
      // Staff notes on entries they added in the app stay internal; the client's own words are shown.
      note: r.channel === 'app' ? null : r.note,
      createdAt: toIso(r.createdAt),
    };
  });
}

/** The client's waiting and notified entries, oldest first. */
export function openWaitlist(db: DbOrTx, clientId: number): WaitlistEntryPublic[] {
  const rows = db
    .select()
    .from(waitlistEntries)
    .where(and(eq(waitlistEntries.clientId, clientId), inArray(waitlistEntries.status, OPEN_WAITLIST_STATUSES)))
    .orderBy(asc(waitlistEntries.createdAt), asc(waitlistEntries.id))
    .all();
  return waitlistEntriesPublic(db, rows);
}

/**
 * `DELETE /public/cabinet/waitlist/:id`: the client's own waiting / notified entry becomes `cancelled` (an already
 * cancelled one stays so); a booked or expired one → `409`; somebody else's → `404`.
 */
export function cancelWaitlistByClient(db: DbOrTx, clientId: number, id: number, now = Date.now()): void {
  const row = db.select().from(waitlistEntries).where(eq(waitlistEntries.id, id)).get();
  if (!row || row.clientId !== clientId) throw notFound('Запись в листе ожидания не найдена');
  if (row.status === 'cancelled') return;
  if (!OPEN_WAITLIST_STATUSES.includes(row.status)) throw conflict('Эта запись в листе ожидания уже неактуальна');
  db.update(waitlistEntries).set({ status: 'cancelled', updatedAt: now }).where(eq(waitlistEntries.id, id)).run();
}
