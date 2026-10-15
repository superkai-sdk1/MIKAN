import { and, asc, eq, gt, inArray, lt, ne, notInArray } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { aftercareTemplates, appointments, clients, employees, services, stockMovements } from '../db/schema.js';
import { badRequest, conflict, scheduleConflict } from '../lib/errors.js';
import { parseSteps, type AppointmentRow } from '../lib/serialize.js';
import { formatShortDate, formatTime, MINUTE_MS } from '../lib/time.js';
import { getAppointmentRow, getClientRow } from './refs.js';
import { studioTimezone } from './settings.js';
import { cancelPendingForAppointment, hasAftercare, scheduleAftercare, syncReminder } from './scheduling.js';
import { applyMovement } from './stock.js';

export const APPOINTMENT_STATUSES = ['scheduled', 'confirmed', 'completed', 'cancelled', 'no_show'] as const;
export type AppointmentStatus = (typeof APPOINTMENT_STATUSES)[number];
const INACTIVE_FOR_OVERLAP = ['cancelled', 'no_show'];

export interface AppointmentInput {
  clientId?: number;
  masterId?: number;
  serviceId?: number | null;
  title?: string | null;
  startsAt?: number;
  endsAt?: number;
  price?: number;
  deposit?: number;
  notes?: string | null;
  status?: AppointmentStatus;
  force?: boolean;
}

export interface AppointmentFilter {
  from?: number;
  to?: number;
  masterId?: number;
  clientId?: number;
  statuses?: string[];
}

export function listAppointments(db: DbOrTx, f: AppointmentFilter): AppointmentRow[] {
  const conditions = [];
  if (f.to !== undefined) conditions.push(lt(appointments.startsAt, f.to));
  if (f.from !== undefined) conditions.push(gt(appointments.endsAt, f.from));
  if (f.masterId !== undefined) conditions.push(eq(appointments.masterId, f.masterId));
  if (f.clientId !== undefined) conditions.push(eq(appointments.clientId, f.clientId));
  if (f.statuses && f.statuses.length > 0) conditions.push(inArray(appointments.status, f.statuses));
  return db
    .select()
    .from(appointments)
    .where(conditions.length ? and(...conditions) : undefined)
    .orderBy(asc(appointments.startsAt), asc(appointments.id))
    .all();
}

function assertOverlapFree(db: DbOrTx, a: { id?: number; masterId: number; startsAt: number; endsAt: number }): void {
  const conditions = [
    eq(appointments.masterId, a.masterId),
    lt(appointments.startsAt, a.endsAt),
    gt(appointments.endsAt, a.startsAt),
    notInArray(appointments.status, INACTIVE_FOR_OVERLAP),
  ];
  if (a.id !== undefined) conditions.push(ne(appointments.id, a.id));
  const clash = db.select().from(appointments).where(and(...conditions)).orderBy(asc(appointments.startsAt)).get();
  if (!clash) return;
  const tz = studioTimezone(db);
  const client = db.select().from(clients).where(eq(clients.id, clash.clientId)).get();
  throw scheduleConflict(
    `У мастера уже есть запись в это время: ${client?.name ?? 'клиент'}, ` +
      `${formatShortDate(clash.startsAt, tz)} ${formatTime(clash.startsAt, tz)}–${formatTime(clash.endsAt, tz)}`,
  );
}

function assertMaster(db: DbOrTx, masterId: number): void {
  const master = db.select().from(employees).where(eq(employees.id, masterId)).get();
  if (!master) throw badRequest('Мастер не найден');
  if (!master.active) throw badRequest(`Сотрудник «${master.name}» отключён`);
}

function loadService(db: DbOrTx, serviceId: number) {
  const service = db.select().from(services).where(eq(services.id, serviceId)).get();
  if (!service) throw badRequest('Услуга не найдена');
  return service;
}

function clientMustExist(db: DbOrTx, clientId: number): void {
  if (!db.select({ id: clients.id }).from(clients).where(eq(clients.id, clientId)).get()) {
    throw badRequest('Клиент не найден');
  }
}

export function createAppointment(db: DbOrTx, input: AppointmentInput): AppointmentRow {
  return db.transaction((tx) => {
    if (input.clientId === undefined) throw badRequest('«Клиент»: обязательное поле');
    if (input.masterId === undefined) throw badRequest('«Мастер»: обязательное поле');
    if (input.startsAt === undefined) throw badRequest('«Начало»: обязательное поле');
    clientMustExist(tx, input.clientId);
    assertMaster(tx, input.masterId);
    const service = input.serviceId != null ? loadService(tx, input.serviceId) : null;
    const endsAt = input.endsAt ?? (service ? input.startsAt + service.durationMin * MINUTE_MS : undefined);
    if (endsAt === undefined) throw badRequest('«Окончание»: обязательное поле');
    if (endsAt <= input.startsAt) throw badRequest('Окончание записи должно быть позже начала');
    const status = input.status ?? 'scheduled';
    if (!input.force && !INACTIVE_FOR_OVERLAP.includes(status)) {
      assertOverlapFree(tx, { masterId: input.masterId, startsAt: input.startsAt, endsAt });
    }
    const now = Date.now();
    const row = tx
      .insert(appointments)
      .values({
        clientId: input.clientId,
        masterId: input.masterId,
        serviceId: service?.id ?? null,
        title: input.title ?? null,
        startsAt: input.startsAt,
        endsAt,
        status,
        price: input.price ?? service?.price ?? 0,
        deposit: input.deposit ?? 0,
        notes: input.notes ?? null,
        completedAt: status === 'completed' ? now : null,
        createdAt: now,
        updatedAt: now,
      })
      .returning()
      .get();
    syncReminder(tx, row, now);
    return row;
  });
}

export function updateAppointment(db: DbOrTx, id: number, input: AppointmentInput): AppointmentRow {
  return db.transaction((tx) => {
    const current = getAppointmentRow(tx, id);
    if (input.clientId !== undefined) clientMustExist(tx, input.clientId);
    if (input.masterId !== undefined && input.masterId !== current.masterId) assertMaster(tx, input.masterId);
    const service = input.serviceId != null ? loadService(tx, input.serviceId) : null;
    const next = {
      clientId: input.clientId ?? current.clientId,
      masterId: input.masterId ?? current.masterId,
      serviceId: input.serviceId === undefined ? current.serviceId : (service?.id ?? null),
      title: input.title === undefined ? current.title : input.title,
      startsAt: input.startsAt ?? current.startsAt,
      endsAt: input.endsAt ?? current.endsAt,
      status: input.status ?? current.status,
      price: input.price ?? current.price,
      deposit: input.deposit ?? current.deposit,
      notes: input.notes === undefined ? current.notes : input.notes,
    };
    if (input.startsAt !== undefined && input.endsAt === undefined) {
      next.endsAt = next.startsAt + (current.endsAt - current.startsAt);
    }
    if (next.endsAt <= next.startsAt) throw badRequest('Окончание записи должно быть позже начала');
    const timingChanged =
      next.startsAt !== current.startsAt || next.endsAt !== current.endsAt || next.masterId !== current.masterId;
    const reactivated = INACTIVE_FOR_OVERLAP.includes(current.status) && !INACTIVE_FOR_OVERLAP.includes(next.status);
    if (!input.force && !INACTIVE_FOR_OVERLAP.includes(next.status) && (timingChanged || reactivated)) {
      assertOverlapFree(tx, { id, masterId: next.masterId, startsAt: next.startsAt, endsAt: next.endsAt });
    }
    const now = Date.now();
    const completedAt = next.status === 'completed' ? (current.completedAt ?? now) : current.completedAt;
    const row = tx
      .update(appointments)
      .set({ ...next, completedAt, updatedAt: now })
      .where(eq(appointments.id, id))
      .returning()
      .get();
    const reminderRelevant =
      timingChanged || next.status !== current.status || next.clientId !== current.clientId ||
      next.serviceId !== current.serviceId;
    if (reminderRelevant) syncReminder(tx, row, now);
    return row;
  });
}

export interface CompleteInput {
  sendAftercare: boolean;
  aftercareTemplateId?: number | null;
  consumables: Array<{ productId: number; quantity: number }>;
}

export function completeAppointment(db: DbOrTx, id: number, input: CompleteInput, employeeId: number) {
  return db.transaction((tx) => {
    const current = getAppointmentRow(tx, id);
    if (current.status === 'cancelled') throw conflict('Нельзя завершить отменённую запись');
    const now = Date.now();
    // Idempotent: a retried/double-tapped complete must not deduct consumables twice.
    const consumablesRecorded =
      tx
        .select({ id: stockMovements.id })
        .from(stockMovements)
        .where(and(eq(stockMovements.appointmentId, id), eq(stockMovements.type, 'usage')))
        .get() !== undefined;
    for (const item of consumablesRecorded ? [] : input.consumables) {
      applyMovement(tx, {
        productId: item.productId,
        delta: -item.quantity,
        type: 'usage',
        appointmentId: id,
        employeeId,
        note: 'Расход на процедуру',
      });
    }
    const completedAt = current.completedAt ?? now;
    const row = tx
      .update(appointments)
      .set({ status: 'completed', completedAt, updatedAt: now })
      .where(eq(appointments.id, id))
      .returning()
      .get();
    cancelPendingForAppointment(tx, id, 'reminder');

    let scheduled = 0;
    if (input.sendAftercare && !hasAftercare(tx, id)) {
      const service = row.serviceId != null ? tx.select().from(services).where(eq(services.id, row.serviceId)).get() : undefined;
      const templateId = input.aftercareTemplateId ?? service?.aftercareTemplateId ?? null;
      if (templateId != null) {
        const template = tx.select().from(aftercareTemplates).where(eq(aftercareTemplates.id, templateId)).get();
        if (!template) throw badRequest('Памятка по уходу не найдена');
        const client = getClientRow(tx, row.clientId);
        scheduled = scheduleAftercare(tx, row, client, parseSteps(template.stepsJson), completedAt);
      }
    }
    return { row, scheduled };
  });
}
