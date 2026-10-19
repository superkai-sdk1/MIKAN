import { randomInt } from 'node:crypto';
import { and, eq, lte, type SQL } from 'drizzle-orm';
import { DateTime } from 'luxon';
import type { DbOrTx } from '../db/client.js';
import { certificateOperations, giftCertificates } from '../db/schema.js';
import { badRequest, conflict, notFound } from '../lib/errors.js';
import type { SaleRow } from '../lib/serialize.js';
import { formatRub } from '../lib/text.js';
import { getRetentionSettings } from './retention-settings.js';
import { studioTimezone } from './settings.js';

/**
 * Gift certificates (docs/API.md «Gift certificates»): issued by a sale's certificate line, spent in parts at
 * checkout until the balance is 0, burnt at `expiresAt` (hourly) or by the owner. Every change of the balance is a
 * `certificate_operations` row, so Σ operations = balance.
 */

export type CertificateStatus = 'active' | 'used' | 'expired' | 'cancelled';
export type CertificateRow = typeof giftCertificates.$inferSelect;
export type CertificateOperationType = 'issue' | 'redeem' | 'refund' | 'cancel' | 'expire';

export const CERTIFICATE_MIN_AMOUNT = 500;
export const CERTIFICATE_MAX_AMOUNT = 100_000;
/** Letters and digits without look-alikes (no 0/O, 1/I/L). */
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_PREFIX = 'MIKAN';
const CODE_BODY_LENGTH = 8;
const CODE_ATTEMPTS = 20;

/**
 * A certificate line of a sale or an open receipt: one at a time, a nominal of 500…100 000 ₽. Returns the nominal.
 */
export function certificateNominal(line: { quantity: number; price?: number | null }, label: string): number {
  if (line.quantity !== 1) throw badRequest(`${label}: сертификат продаётся по одному — укажите количество 1`);
  if (line.price == null) throw badRequest(`${label}: укажите номинал сертификата`);
  if (line.price < CERTIFICATE_MIN_AMOUNT || line.price > CERTIFICATE_MAX_AMOUNT) {
    throw badRequest(`Номинал сертификата — от ${formatRub(CERTIFICATE_MIN_AMOUNT)} до ${formatRub(CERTIFICATE_MAX_AMOUNT)}`);
  }
  return line.price;
}

/** The discount never applies to a certificate line: at most the sum of the other lines. */
export function assertDiscountSparesCertificates(discount: number, subtotal: number, certificateTotal: number): void {
  if (certificateTotal > 0 && discount > subtotal - certificateTotal) {
    throw badRequest('Скидка не распространяется на подарочный сертификат: она не может быть больше суммы остальных позиций');
  }
}

/** The name of a certificate line in a sale: «Подарочный сертификат MIKAN-7K3Q-9F2D». */
export const certificateLineName = (code: string): string => `Подарочный сертификат ${code}`;
/** Before the code is issued (validation, the QR cart). */
export const CERTIFICATE_LINE_NAME = 'Подарочный сертификат';

export function generateCertificateCode(): string {
  let body = '';
  for (let i = 0; i < CODE_BODY_LENGTH; i += 1) body += CODE_ALPHABET[randomInt(0, CODE_ALPHABET.length)];
  return `${CODE_PREFIX}-${body.slice(0, 4)}-${body.slice(4)}`;
}

/** Cyrillic letters typed for their Latin twins. */
const LOOK_ALIKES: Record<string, string> = { А: 'A', В: 'B', Е: 'E', К: 'K', М: 'M', Н: 'H', Р: 'P', С: 'C', Т: 'T', У: 'Y', Х: 'X' };

/**
 * «mikan-7k3q-9f2d», «7K3Q 9F2D», «МИКАН7К3Q9F2D» → «MIKAN-7K3Q-9F2D»: case, dashes, spaces, the prefix and Cyrillic
 * look-alike letters do not matter. Null when it cannot be a code.
 */
export function normalizeCertificateCode(input: string): string | null {
  const upper = input.trim().toUpperCase().replace(/^(MIKAN|МИКАН)/, '');
  const body = [...upper].map((ch) => LOOK_ALIKES[ch] ?? ch).join('').replace(/[^A-Z0-9]/g, '');
  if (body.length !== CODE_BODY_LENGTH) return null;
  return `${CODE_PREFIX}-${body.slice(0, 4)}-${body.slice(4)}`;
}

/** The status as of `now`: an active certificate past `expiresAt` is expired before the hourly job records it. */
export function statusOf(row: Pick<CertificateRow, 'status' | 'expiresAt'>, now: number): CertificateStatus {
  if (row.status === 'active' && row.expiresAt != null && row.expiresAt <= now) return 'expired';
  return row.status as CertificateStatus;
}

export function getCertificateRow(db: DbOrTx, id: number): CertificateRow {
  const row = db.select().from(giftCertificates).where(eq(giftCertificates.id, id)).get();
  if (!row) throw notFound('Сертификат не найден');
  return row;
}

export function findCertificateByCode(db: DbOrTx, input: string): CertificateRow | null {
  const code = normalizeCertificateCode(input);
  if (!code) return null;
  return db.select().from(giftCertificates).where(eq(giftCertificates.code, code)).get() ?? null;
}

function addOperation(
  db: DbOrTx,
  certificateId: number,
  type: CertificateOperationType,
  amount: number,
  v: { saleId?: number | null; employeeId?: number | null; now: number },
): void {
  db.insert(certificateOperations)
    .values({ certificateId, type, amount, saleId: v.saleId ?? null, employeeId: v.employeeId ?? null, createdAt: v.now })
    .run();
}

function setCertificate(db: DbOrTx, id: number, values: Partial<CertificateRow>, now: number): CertificateRow {
  return db.update(giftCertificates).set({ ...values, updatedAt: now }).where(eq(giftCertificates.id, id)).returning().get()!;
}

function uniqueCode(db: DbOrTx): string {
  for (let i = 0; i < CODE_ATTEMPTS; i += 1) {
    const code = generateCertificateCode();
    if (!db.select({ id: giftCertificates.id }).from(giftCertificates).where(eq(giftCertificates.code, code)).get()) return code;
  }
  throw new Error('could not generate a unique certificate code');
}

export interface IssueInput {
  amount: number;
  recipientName: string | null;
  note: string | null;
  buyerClientId: number | null;
  saleId: number;
  employeeId: number | null;
  now: number;
}

/** A new active certificate for a sold certificate line: valid `certificates.validityMonths` from now. */
export function issueCertificate(db: DbOrTx, input: IssueInput): CertificateRow {
  const months = getRetentionSettings(db).certificates.validityMonths;
  const expiresAt =
    months == null ? null : DateTime.fromMillis(input.now, { zone: studioTimezone(db) }).plus({ months }).toMillis();
  const row = db
    .insert(giftCertificates)
    .values({
      code: uniqueCode(db),
      amount: input.amount,
      balance: input.amount,
      status: 'active',
      expiresAt,
      buyerClientId: input.buyerClientId,
      recipientName: input.recipientName,
      note: input.note,
      saleId: input.saleId,
      createdBy: input.employeeId,
      createdAt: input.now,
      updatedAt: input.now,
    })
    .returning()
    .get();
  addOperation(db, row.id, 'issue', input.amount, { saleId: input.saleId, employeeId: input.employeeId, now: input.now });
  return row;
}

const STATUS_REASONS: Record<CertificateStatus, string> = {
  active: '',
  used: 'он уже использован',
  expired: 'срок действия истёк',
  cancelled: 'он аннулирован',
};

export interface CertificatePaymentInput {
  code: string;
  amount: number;
}

export interface CertificateRedemption {
  certificate: CertificateRow;
  amount: number;
}

/** Checks the certificates a checkout spends (nothing is written): known, active, not expired, enough balance. */
export function resolveRedemptions(db: DbOrTx, inputs: CertificatePaymentInput[], now = Date.now()): CertificateRedemption[] {
  const seen = new Set<number>();
  return inputs.map(({ code, amount }) => {
    const certificate = findCertificateByCode(db, code);
    if (!certificate) throw badRequest(`Сертификат ${normalizeCertificateCode(code) ?? code.trim()} не найден`);
    if (seen.has(certificate.id)) throw badRequest(`Сертификат ${certificate.code} указан дважды`);
    seen.add(certificate.id);
    const status = statusOf(certificate, now);
    if (status !== 'active') throw conflict(`Сертификат ${certificate.code} не действует: ${STATUS_REASONS[status]}`);
    if (amount > certificate.balance) throw conflict(`На сертификате ${certificate.code} осталось ${formatRub(certificate.balance)}`);
    return { certificate, amount };
  });
}

/** Spends the checked amounts for the sale; a certificate spent to 0 becomes `used`. */
export function redeemCertificates(
  db: DbOrTx,
  redemptions: CertificateRedemption[],
  saleId: number,
  employeeId: number | null,
  now: number,
): void {
  for (const { certificate, amount } of redemptions) {
    const balance = certificate.balance - amount;
    setCertificate(db, certificate.id, { balance, status: balance === 0 ? 'used' : 'active' }, now);
    addOperation(db, certificate.id, 'redeem', -amount, { saleId, employeeId, now });
  }
}

function operationsOf(db: DbOrTx, where: SQL | undefined) {
  return db.select().from(certificateOperations).where(where).all();
}

/** Net amount spent from a certificate (redeemed minus given back by refunds). */
function spentFrom(db: DbOrTx, certificateId: number): number {
  return -operationsOf(db, eq(certificateOperations.certificateId, certificateId))
    .filter((op) => op.type === 'redeem' || op.type === 'refund')
    .reduce((sum, op) => sum + op.amount, 0);
}

/** A sale that sold certificates can be refunded only while none of them has been spent. */
export function assertCertificatesRefundable(db: DbOrTx, saleId: number): void {
  const sold = db.select().from(giftCertificates).where(eq(giftCertificates.saleId, saleId)).all();
  for (const certificate of sold) {
    if (spentFrom(db, certificate.id) > 0) {
      throw conflict(`Сертификат ${certificate.code} уже частично оплачен покупками — чек вернуть нельзя`);
    }
  }
}

/**
 * A refunded sale: what it paid with certificates goes back to them (burning at once with a certificate that has
 * expired or been cancelled since), and the certificates it sold are cancelled.
 */
export function reverseSaleCertificates(db: DbOrTx, sale: SaleRow, employeeId: number | null, now: number): void {
  const v = { saleId: sale.id, employeeId, now };
  const redeemed = operationsOf(db, and(eq(certificateOperations.saleId, sale.id), eq(certificateOperations.type, 'redeem')));
  for (const op of redeemed) {
    const certificate = getCertificateRow(db, op.certificateId);
    const back = -op.amount;
    addOperation(db, certificate.id, 'refund', back, v);
    const lapsed = certificate.expiresAt != null && certificate.expiresAt <= now;
    const status: CertificateStatus | null =
      certificate.status === 'cancelled' ? 'cancelled' : certificate.status === 'expired' || lapsed ? 'expired' : null;
    if (status) {
      // What it still held burns with what came back (also a used or active one past expiresAt the job has not reached).
      addOperation(db, certificate.id, status === 'cancelled' ? 'cancel' : 'expire', -(certificate.balance + back), v);
      setCertificate(db, certificate.id, { status, balance: 0 }, now);
    } else {
      setCertificate(db, certificate.id, { status: 'active', balance: certificate.balance + back }, now);
    }
  }
  const sold = db.select().from(giftCertificates).where(eq(giftCertificates.saleId, sale.id)).all();
  for (const certificate of sold) {
    if (certificate.status === 'cancelled') continue;
    if (certificate.balance > 0) addOperation(db, certificate.id, 'cancel', -certificate.balance, v);
    setCertificate(db, certificate.id, { status: 'cancelled', balance: 0 }, now);
  }
}

/** Records the expiry of every active certificate past `expiresAt` (the hourly job): its balance burns. */
export function expireCertificates(db: DbOrTx, now = Date.now()): { certificates: number; amount: number } {
  return db.transaction((tx) => {
    const due = tx
      .select()
      .from(giftCertificates)
      .where(and(eq(giftCertificates.status, 'active'), lte(giftCertificates.expiresAt, now)))
      .all();
    for (const certificate of due) {
      if (certificate.balance > 0) addOperation(tx, certificate.id, 'expire', -certificate.balance, { now });
      setCertificate(tx, certificate.id, { status: 'expired', balance: 0 }, now);
    }
    return { certificates: due.length, amount: due.reduce((sum, c) => sum + c.balance, 0) };
  });
}

/** The owner cancels an active certificate: the balance burns; the reason is kept in its note. */
export function cancelCertificate(db: DbOrTx, id: number, reason: string, employeeId: number, now = Date.now()): CertificateRow {
  return db.transaction((tx) => {
    const certificate = getCertificateRow(tx, id);
    const status = statusOf(certificate, now);
    if (status !== 'active') throw conflict(`Сертификат ${certificate.code} уже не действует: ${STATUS_REASONS[status]}`);
    if (certificate.balance > 0) addOperation(tx, id, 'cancel', -certificate.balance, { employeeId, now });
    const note = [certificate.note?.trim(), `Аннулирован: ${reason}`].filter(Boolean).join('\n');
    return setCertificate(tx, id, { status: 'cancelled', balance: 0, note }, now);
  });
}

export interface CertificatePatch {
  recipientName?: string | null;
  note?: string | null;
  /** `null` — never expires; checked by the caller to be the owner's. */
  expiresAt?: number | null;
}

/** Edits the recipient, the note and (the owner) the expiry of a certificate that has not burnt. */
export function updateCertificate(db: DbOrTx, id: number, patch: CertificatePatch, now = Date.now()): CertificateRow {
  const certificate = getCertificateRow(db, id);
  const values: Partial<CertificateRow> = {};
  if (patch.recipientName !== undefined) values.recipientName = patch.recipientName;
  if (patch.note !== undefined) values.note = patch.note;
  if (patch.expiresAt !== undefined && patch.expiresAt !== certificate.expiresAt) {
    const status = statusOf(certificate, now);
    if (status === 'expired' || status === 'cancelled') {
      throw conflict(`Сертификат ${certificate.code} уже не действует — срок изменить нельзя`);
    }
    if (patch.expiresAt != null && patch.expiresAt <= now) throw badRequest('Срок действия должен быть в будущем');
    values.expiresAt = patch.expiresAt;
  }
  return setCertificate(db, id, values, now);
}
