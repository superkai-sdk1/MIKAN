import { and, eq, gt, inArray } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { appointments, clients, employees, scheduledMessages, services } from '../db/schema.js';
import type { AftercareStep, AppointmentRow, ClientRow } from '../lib/serialize.js';
import { aftercareSendAt, formatHumanDateTime, HOUR_MS } from '../lib/time.js';
import { serviceLinesByAppointment } from './refs.js';
import { getBotSettings, getStudioSettings, type StudioSettings } from './settings.js';

export const ACTIVE_APPOINTMENT_STATUSES = ['scheduled', 'confirmed'] as const;

export function aftercareText(studioName: string, dayOffset: number, text: string): string {
  const header = dayOffset === 0 ? `${studioName} · уход после процедуры` : `${studioName} · уход, день ${dayOffset}`;
  return `${header}\n\n${text.trim()}`;
}

export function reminderText(
  studio: StudioSettings,
  startsAt: number,
  serviceNames: string[],
  masterName: string | null,
): string {
  const lines = [
    `🗓 Напоминаем о записи в ${studio.name}`,
    `Когда: ${formatHumanDateTime(startsAt, studio.timezone)}`,
  ];
  if (serviceNames.length > 0) lines.push(`${serviceNames.length > 1 ? 'Услуги' : 'Услуга'}: ${serviceNames.join(', ')}`);
  if (masterName) lines.push(`Мастер: ${masterName}`);
  if (studio.address.trim()) lines.push(`Адрес: ${studio.address.trim()}`);
  lines.push('', 'Если планы изменились — пожалуйста, напишите нам здесь.');
  return lines.join('\n');
}

export function cancelPendingForAppointment(db: DbOrTx, appointmentId: number, kind: 'reminder' | 'aftercare'): number {
  const result = db
    .update(scheduledMessages)
    .set({ status: 'cancelled' })
    .where(
      and(
        eq(scheduledMessages.appointmentId, appointmentId),
        eq(scheduledMessages.kind, kind),
        eq(scheduledMessages.status, 'pending'),
      ),
    )
    .run();
  return result.changes;
}

/** What the reminder names: the booked service lines, else the legacy service, else the appointment title. */
function reminderServiceNames(db: DbOrTx, appointment: AppointmentRow): string[] {
  const lines = serviceLinesByAppointment(db, [appointment.id]).get(appointment.id) ?? [];
  if (lines.length > 0) return lines.map((l) => l.name);
  const legacy =
    appointment.serviceId != null
      ? db.select().from(services).where(eq(services.id, appointment.serviceId)).get()
      : undefined;
  const name = legacy?.name ?? appointment.title;
  return name ? [name] : [];
}

/** Replaces the pending reminder of an appointment according to its current state. */
export function syncReminder(db: DbOrTx, appointment: AppointmentRow, now = Date.now()): void {
  cancelPendingForAppointment(db, appointment.id, 'reminder');
  if (!(ACTIVE_APPOINTMENT_STATUSES as readonly string[]).includes(appointment.status)) return;
  const client = db.select().from(clients).where(eq(clients.id, appointment.clientId)).get();
  if (!client?.telegramChatId || !client.botEnabled) return;
  const bot = getBotSettings(db);
  if (!bot.remindersEnabled) return;
  const sendAt = appointment.startsAt - bot.reminderHoursBefore * HOUR_MS;
  if (sendAt <= now) return;
  const studio = getStudioSettings(db);
  const master = db.select().from(employees).where(eq(employees.id, appointment.masterId)).get();
  db.insert(scheduledMessages)
    .values({
      chatId: client.telegramChatId,
      clientId: client.id,
      appointmentId: appointment.id,
      kind: 'reminder',
      sendAt,
      text: reminderText(studio, appointment.startsAt, reminderServiceNames(db, appointment), master?.name ?? null),
      status: 'pending',
      createdAt: now,
    })
    .run();
}

/** After a client links Telegram, create reminders for their upcoming appointments. */
export function syncRemindersForClient(db: DbOrTx, clientId: number, now = Date.now()): void {
  const upcoming = db
    .select()
    .from(appointments)
    .where(
      and(
        eq(appointments.clientId, clientId),
        gt(appointments.startsAt, now),
        inArray(appointments.status, [...ACTIVE_APPOINTMENT_STATUSES]),
      ),
    )
    .all();
  for (const appointment of upcoming) syncReminder(db, appointment, now);
}

/** Schedules every template step; returns how many messages were created. */
export function scheduleAftercare(
  db: DbOrTx,
  appointment: AppointmentRow,
  client: ClientRow,
  steps: AftercareStep[],
  completedAt: number,
): number {
  if (!client.telegramChatId || !client.botEnabled || steps.length === 0) return 0;
  const studio = getStudioSettings(db);
  const bot = getBotSettings(db);
  const now = Date.now();
  const rows = [...steps]
    .sort((a, b) => a.dayOffset - b.dayOffset)
    .map((step) => ({
      chatId: client.telegramChatId!,
      clientId: client.id,
      appointmentId: appointment.id,
      kind: 'aftercare',
      sendAt: aftercareSendAt(completedAt, step.dayOffset, bot.aftercareHour, studio.timezone),
      text: aftercareText(studio.name, step.dayOffset, step.text),
      status: 'pending',
      createdAt: now,
    }));
  db.insert(scheduledMessages).values(rows).run();
  return rows.length;
}

export function hasAftercare(db: DbOrTx, appointmentId: number): boolean {
  const row = db
    .select({ id: scheduledMessages.id })
    .from(scheduledMessages)
    .where(
      and(
        eq(scheduledMessages.appointmentId, appointmentId),
        eq(scheduledMessages.kind, 'aftercare'),
        inArray(scheduledMessages.status, ['pending', 'sent']),
      ),
    )
    .get();
  return row !== undefined;
}
