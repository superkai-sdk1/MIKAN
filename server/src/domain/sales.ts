import { and, asc, count, desc, eq, gte, lt, max } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { appointments, clients, products, productVariants, saleItems, sales, services } from '../db/schema.js';
import { badRequest, conflict, insufficientStock } from '../lib/errors.js';
import { sizedName } from '../lib/jewelry.js';
import type { AppointmentRow, ProductRow, SaleItemRow, SaleRow } from '../lib/serialize.js';
import { formatRub } from '../lib/text.js';
import { getOpenShift } from './cash.js';
import { applyDeposit, cancelPendingDepositCodes, heldDeposit, unapplyDeposit } from './deposits.js';
import { getAppointmentRow, getSaleRow, serializeSales } from './refs.js';
import { cancelPendingForAppointment } from './scheduling.js';
import { applyMovement, getProductRow, insufficientMessage, resolveVariant, returnVariantId } from './stock.js';

export interface SaleItemInput {
  type: 'product' | 'service';
  productId?: number | null;
  /** The size sold; older builds omit it (allowed only for a product with one size). */
  variantId?: number | null;
  serviceId?: number | null;
  name?: string | null;
  quantity: number;
  price?: number | null;
}

export interface SalePayments {
  cash: number;
  card: number;
  transfer: number;
  /** Only from a QR payment the bank confirmed (see qr-payments.ts); `POST /sales` rejects it. */
  qr: number;
  /**
   * Covered by the appointment's held prepayment. `undefined` = the client predates prepayments (it never sends the
   * key), which is refused while the appointment holds one, so the prepayment cannot be charged a second time.
   */
  deposit?: number;
}

export interface SaleInput {
  clientId?: number | null;
  appointmentId?: number | null;
  items: SaleItemInput[];
  discount: number;
  payments: SalePayments;
  note?: string | null;
}

interface ResolvedItem {
  type: 'product' | 'service';
  productId: number | null;
  variantId: number | null;
  variantName: string | null;
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
    const variant = resolveVariant(db, product, item.variantId, severalSizesForSale(product), `${label}: размер не найден`);
    const price = item.price ?? variant.price ?? product.price;
    return {
      type: 'product',
      productId: product.id,
      variantId: variant.id,
      variantName: variant.name.trim() || null,
      serviceId: null,
      name: sizedName(product.name, variant.name),
      quantity: item.quantity,
      price,
      total: price * item.quantity,
    };
  }
  const service = item.serviceId != null ? db.select().from(services).where(eq(services.id, item.serviceId)).get() : undefined;
  if (item.serviceId != null && !service) throw badRequest(`${label}: услуга не найдена`);
  const name = item.name?.trim() || service?.name;
  if (!name) throw badRequest(`${label}: укажите название услуги`);
  const price = item.price ?? service?.price;
  if (price == null) throw badRequest(`${label}: укажите цену`);
  return {
    type: 'service',
    productId: null,
    variantId: null,
    variantName: null,
    serviceId: service?.id ?? null,
    name,
    quantity: item.quantity,
    price,
    total: price * item.quantity,
  };
}

/** An older build sold a product that now has several sizes: it cannot say which one. */
const severalSizesForSale = (product: ProductRow) => () =>
  conflict(`У «${product.name}» несколько размеров. Обновите приложение MIKAN, чтобы выбрать размер.`);

interface PreparedSale {
  items: ResolvedItem[];
  subtotal: number;
  total: number;
  clientId: number | null;
  appointment: AppointmentRow | null;
}

/** Quantities summed per size, so two lines of one size are checked against its stock together. */
function assertInStock(db: DbOrTx, items: ResolvedItem[]): void {
  const wanted = new Map<number, { productId: number; quantity: number }>();
  for (const item of items) {
    if (item.productId == null || item.variantId == null) continue;
    const entry = wanted.get(item.variantId) ?? { productId: item.productId, quantity: 0 };
    entry.quantity += item.quantity;
    wanted.set(item.variantId, entry);
  }
  for (const [variantId, { productId, quantity }] of wanted) {
    const variant = db.select().from(productVariants).where(eq(productVariants.id, variantId)).get()!;
    if (variant.quantity < quantity) throw insufficientStock(insufficientMessage(getProductRow(db, productId), variant));
  }
}

/** The prepayment part of a checkout must be held for the appointment (and be sent at all while one is held). */
function assertDepositCovers(db: DbOrTx, appointmentId: number, deposit: number | undefined): void {
  const held = heldDeposit(db, appointmentId);
  if (deposit === undefined) {
    if (held > 0) {
      throw conflict(`По записи внесена предоплата ${formatRub(held)}. Обновите приложение MIKAN, чтобы зачесть её в чеке.`);
    }
    return;
  }
  if (deposit > held) {
    throw conflict(held > 0 ? `За записью только ${formatRub(held)} предоплаты` : 'По записи нет внесённой предоплаты');
  }
}

/** Validates a sale without writing anything: items, totals, payments, appointment, client and stock. */
export function prepareSale(db: DbOrTx, input: SaleInput): PreparedSale {
  if (input.items.length === 0) throw badRequest('Добавьте хотя бы одну позицию');
  const items = input.items.map((item, i) => resolveItem(db, item, i));
  const subtotal = items.reduce((sum, i) => sum + i.total, 0);
  if (input.discount > subtotal) throw badRequest('Скидка не может быть больше суммы чека');
  const total = subtotal - input.discount;
  const { cash, card, transfer, qr } = input.payments;
  const deposit = input.payments.deposit ?? 0;
  const paid = cash + card + transfer + qr + deposit;
  if (paid !== total) {
    throw badRequest(`Сумма оплат (${formatRub(paid)}) не совпадает с итогом (${formatRub(total)})`);
  }
  if (deposit > 0 && input.appointmentId == null) throw badRequest('Предоплату можно зачесть только в чеке по записи');

  let clientId = input.clientId ?? null;
  const appointment = input.appointmentId != null ? getAppointmentRow(db, input.appointmentId) : null;
  if (appointment) {
    if (appointment.paidOutside) throw conflict('Запись уже оплачена до перехода на MIKAN (перенесена из YCLIENTS)');
    if (appointment.saleId != null) {
      const linked = db.select().from(sales).where(eq(sales.id, appointment.saleId)).get();
      if (linked && linked.status === 'completed') throw conflict(`Запись уже оплачена (чек №${linked.number})`);
    }
    clientId = clientId ?? appointment.clientId;
    assertDepositCovers(db, appointment.id, input.payments.deposit);
  }
  if (clientId != null && !db.select({ id: clients.id }).from(clients).where(eq(clients.id, clientId)).get()) {
    throw badRequest('Клиент не найден');
  }
  assertInStock(db, items);
  return { items, subtotal, total, clientId, appointment };
}

export function createSale(db: DbOrTx, input: SaleInput, employeeId: number): SaleRow {
  return db.transaction((tx) => {
    const { items, subtotal, total, clientId, appointment } = prepareSale(tx, input);

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
        payQr: input.payments.qr,
        payDeposit: input.payments.deposit ?? 0,
        status: 'completed',
        note: input.note ?? null,
        createdAt: now,
      })
      .returning()
      .get();
    tx.insert(saleItems).values(items.map((i) => ({ ...i, saleId: sale.id }))).run();
    for (const item of items) {
      if (item.type === 'product' && item.productId != null && item.variantId != null) {
        applyMovement(tx, {
          productId: item.productId,
          variantId: item.variantId,
          delta: -item.quantity,
          type: 'sale',
          saleId: sale.id,
          employeeId,
        });
      }
    }
    applyDeposit(tx, sale, sale.payDeposit, employeeId);
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
      cancelPendingDepositCodes(tx, appointment.id, now);
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
    unapplyDeposit(tx, updated, openShift?.id ?? null, employeeId, now);
    if (input.restock) {
      const items = tx.select().from(saleItems).where(eq(saleItems.saleId, id)).all();
      for (const item of items) {
        if (item.type !== 'product' || item.productId == null) continue;
        applyMovement(tx, {
          productId: item.productId,
          variantId: returnVariantId(tx, soldVariantId(tx, item.productId, item)),
          delta: item.quantity,
          type: 'return',
          saleId: id,
          employeeId,
          note: input.reason,
        });
      }
    }
    return updated;
  });
}

/**
 * The size a sold item goes back to. Every product item names one (items sold before sizes existed were linked to
 * their product's only size by the migration); a hand-edited row without it falls back to the product's first size.
 */
function soldVariantId(db: DbOrTx, productId: number, item: SaleItemRow): number {
  if (item.variantId != null) return item.variantId;
  const first = db
    .select({ id: productVariants.id })
    .from(productVariants)
    .where(eq(productVariants.productId, productId))
    .orderBy(asc(productVariants.archived), asc(productVariants.position), asc(productVariants.id))
    .get();
  if (!first) throw conflict(`Не найден размер товара «${item.name}» для возврата на склад`);
  return first.id;
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
