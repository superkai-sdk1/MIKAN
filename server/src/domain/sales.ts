import { and, count, desc, eq, gte, lt, max } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { appointments, clients, products, saleItems, sales, services } from '../db/schema.js';
import { badRequest, conflict } from '../lib/errors.js';
import type { SaleRow } from '../lib/serialize.js';
import { formatRub } from '../lib/text.js';
import { getOpenShift } from './cash.js';
import { getAppointmentRow, getSaleRow, serializeSales } from './refs.js';
import { cancelPendingForAppointment } from './scheduling.js';
import { applyMovement } from './stock.js';

export interface SaleItemInput {
  type: 'product' | 'service';
  productId?: number | null;
  serviceId?: number | null;
  name?: string | null;
  quantity: number;
  price?: number | null;
}

export interface SaleInput {
  clientId?: number | null;
  appointmentId?: number | null;
  items: SaleItemInput[];
  discount: number;
  payments: { cash: number; card: number; transfer: number };
  note?: string | null;
}

interface ResolvedItem {
  type: 'product' | 'service';
  productId: number | null;
  serviceId: number | null;
  name: string;
  quantity: number;
  price: number;
  total: number;
}

function resolveItem(db: DbOrTx, item: SaleItemInput, position: number): ResolvedItem {
  const label = `Позиция №${position + 1}`;
  if (item.type === 'product') {
    if (item.productId == null) throw badRequest(`${label}: выберите товар`);
    const product = db.select().from(products).where(eq(products.id, item.productId)).get();
    if (!product) throw badRequest(`${label}: товар не найден`);
    if (product.kind !== 'jewelry') throw badRequest(`«${product.name}» — расходник, его нельзя продать`);
    const price = item.price ?? product.price;
    return { type: 'product', productId: product.id, serviceId: null, name: product.name, quantity: item.quantity, price, total: price * item.quantity };
  }
  const service = item.serviceId != null ? db.select().from(services).where(eq(services.id, item.serviceId)).get() : undefined;
  if (item.serviceId != null && !service) throw badRequest(`${label}: услуга не найдена`);
  const name = item.name?.trim() || service?.name;
  if (!name) throw badRequest(`${label}: укажите название услуги`);
  const price = item.price ?? service?.price;
  if (price == null) throw badRequest(`${label}: укажите цену`);
  return { type: 'service', productId: null, serviceId: service?.id ?? null, name, quantity: item.quantity, price, total: price * item.quantity };
}

export function createSale(db: DbOrTx, input: SaleInput, employeeId: number): SaleRow {
  return db.transaction((tx) => {
    if (input.items.length === 0) throw badRequest('Добавьте хотя бы одну позицию');
    const items = input.items.map((item, i) => resolveItem(tx, item, i));
    const subtotal = items.reduce((sum, i) => sum + i.total, 0);
    if (input.discount > subtotal) throw badRequest('Скидка не может быть больше суммы чека');
    const total = subtotal - input.discount;
    const paid = input.payments.cash + input.payments.card + input.payments.transfer;
    if (paid !== total) {
      throw badRequest(`Сумма оплат (${formatRub(paid)}) не совпадает с итогом (${formatRub(total)})`);
    }

    let clientId = input.clientId ?? null;
    const appointment = input.appointmentId != null ? getAppointmentRow(tx, input.appointmentId) : null;
    if (appointment) {
      if (appointment.saleId != null) {
        const linked = tx.select().from(sales).where(eq(sales.id, appointment.saleId)).get();
        if (linked && linked.status === 'completed') throw conflict(`Запись уже оплачена (чек №${linked.number})`);
      }
      clientId = clientId ?? appointment.clientId;
    }
    if (clientId != null && !tx.select({ id: clients.id }).from(clients).where(eq(clients.id, clientId)).get()) {
      throw badRequest('Клиент не найден');
    }

    const now = Date.now();
    const number = (tx.select({ n: max(sales.number) }).from(sales).get()?.n ?? 0) + 1;
    const sale = tx
      .insert(sales)
      .values({
        number,
        clientId,
        employeeId,
        appointmentId: appointment?.id ?? null,
        shiftId: getOpenShift(tx)?.id ?? null,
        subtotal,
        discount: input.discount,
        total,
        payCash: input.payments.cash,
        payCard: input.payments.card,
        payTransfer: input.payments.transfer,
        status: 'completed',
        note: input.note ?? null,
        createdAt: now,
      })
      .returning()
      .get();
    tx.insert(saleItems).values(items.map((i) => ({ ...i, saleId: sale.id }))).run();
    for (const item of items) {
      if (item.type === 'product' && item.productId != null) {
        applyMovement(tx, { productId: item.productId, delta: -item.quantity, type: 'sale', saleId: sale.id, employeeId });
      }
    }
    if (appointment) {
      const completing = appointment.status !== 'completed';
      tx.update(appointments)
        .set({
          saleId: sale.id,
          status: 'completed',
          completedAt: appointment.completedAt ?? (completing ? now : null),
          updatedAt: now,
        })
        .where(eq(appointments.id, appointment.id))
        .run();
      if (completing) cancelPendingForAppointment(tx, appointment.id, 'reminder');
    }
    return sale;
  });
}

export function refundSale(db: DbOrTx, id: number, input: { reason: string; restock: boolean }, employeeId: number): SaleRow {
  return db.transaction((tx) => {
    const sale = getSaleRow(tx, id);
    if (sale.status === 'refunded') throw conflict(`Чек №${sale.number} уже возвращён`);
    const openShift = getOpenShift(tx);
    if (sale.payCash > 0 && !openShift) {
      // Cash handed back must be recorded against a shift, otherwise the drawer stops balancing.
      throw conflict(`Чтобы вернуть ${formatRub(sale.payCash)} наличными, сначала откройте кассовую смену`);
    }
    const now = Date.now();
    const updated = tx
      .update(sales)
      .set({
        status: 'refunded',
        refundedAt: now,
        refundReason: input.reason,
        refundShiftId: openShift?.id ?? null,
        refundedById: employeeId,
      })
      .where(eq(sales.id, id))
      .returning()
      .get();
    if (input.restock) {
      const items = tx.select().from(saleItems).where(eq(saleItems.saleId, id)).all();
      for (const item of items) {
        if (item.type === 'product' && item.productId != null) {
          applyMovement(tx, { productId: item.productId, delta: item.quantity, type: 'return', saleId: id, employeeId, note: input.reason });
        }
      }
    }
    return updated;
  });
}

export function listSales(
  db: DbOrTx,
  f: { from?: number; to?: number; clientId?: number; limit: number; offset: number },
) {
  const conditions = [];
  if (f.from !== undefined) conditions.push(gte(sales.createdAt, f.from));
  if (f.to !== undefined) conditions.push(lt(sales.createdAt, f.to));
  if (f.clientId !== undefined) conditions.push(eq(sales.clientId, f.clientId));
  const where = conditions.length ? and(...conditions) : undefined;
  const rows = db.select().from(sales).where(where).orderBy(desc(sales.createdAt), desc(sales.id)).limit(f.limit).offset(f.offset).all();
  const total = db.select({ n: count() }).from(sales).where(where).get()?.n ?? 0;
  return { items: serializeSales(db, rows), total };
}
