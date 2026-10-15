import { eq, inArray } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { appointments, clients, employees, products, saleItems, sales, services } from '../db/schema.js';
import { notFound } from '../lib/errors.js';
import {
  appointmentOut,
  clientRef,
  employeeRef,
  saleOut,
  serviceRef,
  type AppointmentOut,
  type AppointmentRow,
  type ClientRow,
  type EmployeeRow,
  type ProductRow,
  type SaleItemRow,
  type SaleOut,
  type SaleRow,
  type ServiceRow,
} from '../lib/serialize.js';

const unique = (ids: Array<number | null | undefined>): number[] => [
  ...new Set(ids.filter((x): x is number => typeof x === 'number')),
];

export function employeesByIds(db: DbOrTx, ids: Array<number | null | undefined>): Map<number, EmployeeRow> {
  const list = unique(ids);
  if (list.length === 0) return new Map();
  return new Map(db.select().from(employees).where(inArray(employees.id, list)).all().map((r) => [r.id, r]));
}

export function clientsByIds(db: DbOrTx, ids: Array<number | null | undefined>): Map<number, ClientRow> {
  const list = unique(ids);
  if (list.length === 0) return new Map();
  return new Map(db.select().from(clients).where(inArray(clients.id, list)).all().map((r) => [r.id, r]));
}

export function servicesByIds(db: DbOrTx, ids: Array<number | null | undefined>): Map<number, ServiceRow> {
  const list = unique(ids);
  if (list.length === 0) return new Map();
  return new Map(db.select().from(services).where(inArray(services.id, list)).all().map((r) => [r.id, r]));
}

export function productsByIds(db: DbOrTx, ids: Array<number | null | undefined>): Map<number, ProductRow> {
  const list = unique(ids);
  if (list.length === 0) return new Map();
  return new Map(db.select().from(products).where(inArray(products.id, list)).all().map((r) => [r.id, r]));
}

const missingEmployee = (id: number) => ({ id, name: 'Удалённый сотрудник', color: '#8E8E93' });
const missingClient = (id: number) => ({ id, name: 'Удалённый клиент', phone: null, telegramLinked: false });

export function serializeAppointments(db: DbOrTx, rows: AppointmentRow[]): AppointmentOut[] {
  const cl = clientsByIds(
    db,
    rows.map((r) => r.clientId),
  );
  const em = employeesByIds(
    db,
    rows.map((r) => r.masterId),
  );
  const sv = servicesByIds(
    db,
    rows.map((r) => r.serviceId),
  );
  return rows.map((a) => {
    const client = cl.get(a.clientId);
    const master = em.get(a.masterId);
    const service = a.serviceId != null ? sv.get(a.serviceId) : undefined;
    return appointmentOut(
      a,
      client ? clientRef(client) : missingClient(a.clientId),
      master ? employeeRef(master) : missingEmployee(a.masterId),
      service ? serviceRef(service) : null,
    );
  });
}

export function getAppointmentRow(db: DbOrTx, id: number): AppointmentRow {
  const row = db.select().from(appointments).where(eq(appointments.id, id)).get();
  if (!row) throw notFound('Запись не найдена');
  return row;
}

export function serializeAppointment(db: DbOrTx, row: AppointmentRow): AppointmentOut {
  const [out] = serializeAppointments(db, [row]);
  return out!;
}

export function serializeSales(db: DbOrTx, rows: SaleRow[]): SaleOut[] {
  if (rows.length === 0) return [];
  const items = db
    .select()
    .from(saleItems)
    .where(
      inArray(
        saleItems.saleId,
        rows.map((r) => r.id),
      ),
    )
    .all();
  const bySale = new Map<number, SaleItemRow[]>();
  for (const item of items) {
    const list = bySale.get(item.saleId) ?? [];
    list.push(item);
    bySale.set(item.saleId, list);
  }
  const cl = clientsByIds(
    db,
    rows.map((r) => r.clientId),
  );
  const em = employeesByIds(
    db,
    rows.map((r) => r.employeeId),
  );
  return rows.map((sale) => {
    const client = sale.clientId != null ? cl.get(sale.clientId) : undefined;
    const employee = em.get(sale.employeeId);
    return saleOut(
      sale,
      (bySale.get(sale.id) ?? []).sort((a, b) => a.id - b.id),
      client ? clientRef(client) : null,
      employee ? employeeRef(employee) : missingEmployee(sale.employeeId),
    );
  });
}

export function getSaleRow(db: DbOrTx, id: number): SaleRow {
  const row = db.select().from(sales).where(eq(sales.id, id)).get();
  if (!row) throw notFound('Чек не найден');
  return row;
}

export function serializeSale(db: DbOrTx, row: SaleRow): SaleOut {
  const [out] = serializeSales(db, [row]);
  return out!;
}

export function getClientRow(db: DbOrTx, id: number): ClientRow {
  const row = db.select().from(clients).where(eq(clients.id, id)).get();
  if (!row) throw notFound('Клиент не найден');
  return row;
}

export function employeeRefOrMissing(map: Map<number, EmployeeRow>, id: number | null) {
  if (id == null) return null;
  const e = map.get(id);
  return e ? employeeRef(e) : missingEmployee(id);
}
