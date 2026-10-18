import { and, asc, eq, gt, inArray, sql } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { products, productServices, productVariants, services } from '../db/schema.js';
import { badRequest, conflict } from '../lib/errors.js';
import type { ThreadType } from '../lib/jewelry.js';
import { parsePhotos, productOut, type ProductOut, type ProductRow, type VariantRow } from '../lib/serialize.js';
import { normalizeSearchTerm } from '../lib/text.js';
import { productScope, resolveCategory } from './categories.js';
import { productSearchFields } from './product-search.js';
import { applyMovement, currentVariants, getProductRow, variantsWithHistory } from './stock.js';

export { productSearchFields } from './product-search.js';

export type ProductKind = 'jewelry' | 'goods' | 'consumable';
export type StockMode = 'quantity' | 'presence';
export type PresenceStatus = 'ok' | 'low' | 'out';

/** A size in `POST/PATCH /products` `variants`; on PATCH an omitted field of an existing size keeps its value. */
export interface VariantInput {
  id?: number | null;
  name?: string | null;
  sku?: string | null;
  price?: number | null;
  cost?: number | null;
  minQuantity?: number;
  /** New sizes only: recorded as a `receipt`. */
  initialQuantity?: number;
}

/** Validated product fields; `undefined` = untouched (PATCH) or the default (POST). */
export interface ProductFields {
  kind?: ProductKind;
  name?: string;
  sku?: string | null;
  category?: string | null;
  material?: string | null;
  threadType?: ThreadType | null;
  thicknessMm?: number | null;
  color?: string | null;
  stone?: string | null;
  supplier?: string | null;
  description?: string | null;
  price?: number;
  cost?: number | null;
  unit?: string;
  photos?: string[];
  /** Older builds: the cover only. */
  photoUrl?: string | null;
  serviceIds?: number[];
  /** Consumables only: `presence` tracks «есть / заканчивается / нет» instead of units. */
  stockMode?: StockMode;
  presenceStatus?: PresenceStatus | null;
  active?: boolean;
  variants?: VariantInput[];
  /** Older builds: the name and minimum of the only size, and (POST) its initial stock. */
  size?: string | null;
  minQuantity?: number;
  initialQuantity?: number;
}

export interface NewProduct extends ProductFields {
  kind: ProductKind;
  name: string;
}

const CONSUMABLE_ONE_SIZE = 'У расходника не может быть нескольких размеров — заведите отдельные позиции';

/** SQL: the product has a current size in stock. */
export const hasSizeInStock = sql`exists (select 1 from ${productVariants} where ${productVariants.productId} = ${products.id} and ${productVariants.archived} = 0 and ${productVariants.quantity} > 0)`;
/**
 * SQL: the product needs restocking — a presence consumable not marked «есть», or some current size of a counted
 * product at or below its minimum.
 */
export const hasLowStock = sql`(case when ${products.stockMode} = 'presence' then ${products.presenceStatus} <> 'ok' else exists (select 1 from ${productVariants} where ${productVariants.productId} = ${products.id} and ${productVariants.archived} = 0 and ${productVariants.quantity} <= ${productVariants.minQuantity}) end)`;

const PRESENCE_ONLY_CONSUMABLES = 'Учёт «есть / нет» — только для расходников';
const PRESENCE_STATUS_NEEDS_MODE = 'Статус наличия задаётся только для расходников с учётом «есть / нет»';

/**
 * Stock mode and presence status after an edit: presence is for consumables only (another kind falls back to
 * counting); switching to presence starts at «есть» when the product has stock, «нет» otherwise.
 */
function stockModeFields(
  kind: string,
  input: Pick<ProductFields, 'stockMode' | 'presenceStatus'>,
  current: { stockMode: string; presenceStatus: string; quantity: number } | null,
): { stockMode: StockMode; presenceStatus: PresenceStatus } {
  if (input.stockMode === 'presence' && kind !== 'consumable') throw badRequest(PRESENCE_ONLY_CONSUMABLES);
  const mode: StockMode = kind !== 'consumable' ? 'quantity' : (input.stockMode ?? (current?.stockMode as StockMode | undefined) ?? 'quantity');
  if (mode !== 'presence') {
    if (input.presenceStatus != null) throw badRequest(PRESENCE_STATUS_NEEDS_MODE);
    return { stockMode: mode, presenceStatus: (current?.presenceStatus as PresenceStatus | undefined) ?? 'ok' };
  }
  const switching = current?.stockMode !== 'presence';
  const fallback: PresenceStatus = switching ? ((current?.quantity ?? 0) > 0 ? 'ok' : 'out') : (current!.presenceStatus as PresenceStatus);
  return { stockMode: mode, presenceStatus: input.presenceStatus ?? fallback };
}

/** Current sizes of the given products in order (`inStockOnly` — only sizes with stock), grouped by product. */
export function variantsByProduct(db: DbOrTx, productIds: number[], opts: { inStockOnly?: boolean } = {}): Map<number, VariantRow[]> {
  const result = new Map<number, VariantRow[]>();
  const ids = [...new Set(productIds)];
  if (ids.length === 0) return result;
  const conditions = [inArray(productVariants.productId, ids), eq(productVariants.archived, false)];
  if (opts.inStockOnly) conditions.push(gt(productVariants.quantity, 0));
  const rows = db
    .select()
    .from(productVariants)
    .where(and(...conditions))
    .orderBy(asc(productVariants.productId), asc(productVariants.position), asc(productVariants.id))
    .all();
  for (const row of rows) result.set(row.productId, [...(result.get(row.productId) ?? []), row]);
  return result;
}

/** Linked catalog services of the given products, in service id order. */
export function serviceIdsByProduct(db: DbOrTx, productIds: number[]): Map<number, number[]> {
  const result = new Map<number, number[]>();
  const ids = [...new Set(productIds)];
  if (ids.length === 0) return result;
  const rows = db
    .select()
    .from(productServices)
    .where(inArray(productServices.productId, ids))
    .orderBy(asc(productServices.productId), asc(productServices.serviceId))
    .all();
  for (const row of rows) result.set(row.productId, [...(result.get(row.productId) ?? []), row.serviceId]);
  return result;
}

export function serializeProducts(db: DbOrTx, rows: ProductRow[]): ProductOut[] {
  const ids = rows.map((r) => r.id);
  const sizes = variantsByProduct(db, ids);
  const links = serviceIdsByProduct(db, ids);
  return rows.map((p) => productOut(p, sizes.get(p.id) ?? [], links.get(p.id) ?? []));
}

export function serializeProduct(db: DbOrTx, row: ProductRow): ProductOut {
  return serializeProducts(db, [row])[0]!;
}

const sizeLabel = (v: Pick<VariantRow, 'name'>) => (v.name.trim() ? `Размер «${v.name.trim()}»` : 'Товар без размера');

/** Names are unique (case-insensitive) and required once there are two sizes; a consumable has one size. */
function checkSizeList(kind: string, sizes: Array<{ name: string }>): void {
  if (sizes.length === 0) throw badRequest('Добавьте хотя бы один размер');
  if (kind === 'consumable' && sizes.length > 1) throw badRequest(CONSUMABLE_ONE_SIZE);
  if (sizes.length > 1) {
    const unnamed = sizes.findIndex((v) => !v.name);
    if (unnamed >= 0) throw badRequest(`Размер №${unnamed + 1}: укажите название размера`);
  }
  const seen = new Set<string>();
  for (const v of sizes) {
    const key = normalizeSearchTerm(v.name);
    if (seen.has(key)) throw badRequest(`Размер «${v.name}» указан дважды`);
    seen.add(key);
  }
}

/** Deduplicated ids of existing services (`400` for an unknown one). */
function checkServiceIds(db: DbOrTx, ids: number[]): number[] {
  const list = [...new Set(ids)];
  if (list.length === 0) return list;
  const found = new Set(db.select({ id: services.id }).from(services).where(inArray(services.id, list)).all().map((r) => r.id));
  if (list.some((id) => !found.has(id))) throw badRequest('Услуга не найдена');
  return list;
}

function writeServiceLinks(db: DbOrTx, productId: number, serviceIds: number[]): void {
  db.delete(productServices).where(eq(productServices.productId, productId)).run();
  if (serviceIds.length) db.insert(productServices).values(serviceIds.map((serviceId) => ({ productId, serviceId }))).run();
}

const photoColumns = (photos: string[]) => ({ photosJson: JSON.stringify(photos), photoUrl: photos[0] ?? null });

/** `photos` replaces them; `photoUrl` alone (older builds) replaces or removes the cover; `undefined` — untouched. */
function nextPhotos(current: ProductRow, input: ProductFields): string[] | undefined {
  if (input.photos !== undefined) return input.photos;
  if (input.photoUrl === undefined) return undefined;
  const rest = parsePhotos(current.photosJson).slice(1);
  return input.photoUrl ? [input.photoUrl, ...rest.filter((p) => p !== input.photoUrl)] : rest;
}

/** Inserts a size; positive `initialQuantity` is recorded as a `receipt` movement. */
function insertSize(
  db: DbOrTx,
  productId: number,
  size: { name: string; sku: string | null; price: number | null; cost: number | null; minQuantity: number; initialQuantity: number },
  position: number,
  employeeId: number | null,
  receiptNote: string,
): void {
  const now = Date.now();
  const { initialQuantity, ...fields } = size;
  const row = db
    .insert(productVariants)
    .values({ ...fields, productId, quantity: 0, position, createdAt: now, updatedAt: now })
    .returning()
    .get();
  if (initialQuantity > 0) {
    applyMovement(db, { productId, variantId: row.id, delta: initialQuantity, type: 'receipt', note: receiptNote, employeeId });
  }
}

/** Inserts a product with its sizes (`variants`, or the legacy single size). Call inside a transaction. */
export function createProduct(db: DbOrTx, input: NewProduct, employeeId: number | null, receiptNote = 'Начальный остаток'): ProductRow {
  const requested = input.variants ?? [{ name: input.size, minQuantity: input.minQuantity, initialQuantity: input.initialQuantity }];
  const sizes = requested.map((v, i) => {
    if (v.id != null) throw badRequest(`Размер №${i + 1} не найден`);
    return {
      name: v.name?.trim() ?? '',
      sku: v.sku ?? null,
      price: v.price ?? null,
      cost: v.cost ?? null,
      minQuantity: v.minQuantity ?? 0,
      initialQuantity: v.initialQuantity ?? 0,
    };
  });
  checkSizeList(input.kind, sizes);
  const serviceIds = checkServiceIds(db, input.serviceIds ?? []);
  const now = Date.now();
  const initialStock = sizes.reduce((sum, v) => sum + v.initialQuantity, 0);
  const base = {
    name: input.name,
    sku: input.sku ?? null,
    category: resolveCategory(db, productScope(input.kind), input.category),
    material: input.material ?? null,
    color: input.color ?? null,
    stone: input.stone ?? null,
    supplier: input.supplier ?? null,
  };
  const created = db
    .insert(products)
    .values({
      ...base,
      ...productSearchFields(base, sizes),
      ...photoColumns(input.photos ?? (input.photoUrl ? [input.photoUrl] : [])),
      kind: input.kind,
      ...stockModeFields(input.kind, input, { stockMode: 'quantity', presenceStatus: 'ok', quantity: initialStock }),
      threadType: input.threadType ?? null,
      thicknessMm: input.thicknessMm ?? null,
      description: input.description ?? null,
      price: input.price ?? 0,
      cost: input.cost ?? null,
      unit: input.unit ?? 'шт',
      active: input.active ?? true,
      createdAt: now,
      updatedAt: now,
    })
    .returning()
    .get();
  sizes.forEach((size, position) => insertSize(db, created.id, size, position, employeeId, receiptNote));
  writeServiceLinks(db, created.id, serviceIds);
  return getProductRow(db, created.id);
}

/**
 * Replaces the sizes with `inputs` (in that order): an item with `id` updates that size, one without adds a size,
 * and a size left out is deleted — or archived when it has history. A size with stock cannot be removed.
 */
function syncSizes(db: DbOrTx, product: ProductRow, kind: string, inputs: VariantInput[], employeeId: number): void {
  const existing = new Map(currentVariants(db, product.id).map((v) => [v.id, v]));
  const sizes = inputs.map((v, i) => {
    const current = v.id != null ? existing.get(v.id) : undefined;
    if (v.id != null && !current) throw badRequest(`Размер №${i + 1} не найден — обновите карточку товара`);
    return {
      id: current?.id ?? null,
      name: v.name !== undefined ? (v.name?.trim() ?? '') : (current?.name ?? ''),
      sku: v.sku !== undefined ? v.sku : (current?.sku ?? null),
      price: v.price !== undefined ? v.price : (current?.price ?? null),
      cost: v.cost !== undefined ? v.cost : (current?.cost ?? null),
      minQuantity: v.minQuantity ?? current?.minQuantity ?? 0,
      initialQuantity: current ? 0 : (v.initialQuantity ?? 0),
    };
  });
  const keptIds = sizes.map((v) => v.id).filter((id): id is number => id != null);
  if (new Set(keptIds).size !== keptIds.length) throw badRequest('Размер указан дважды');
  checkSizeList(kind, sizes);

  const removed = [...existing.values()].filter((v) => !keptIds.includes(v.id));
  const archivedByName = archivedSizesByName(db, product.id);
  const withStock = removed.find((v) => v.quantity > 0);
  if (withStock) {
    throw conflict(`${sizeLabel(withStock)}: на складе ${withStock.quantity} ${product.unit} — спишите остаток, прежде чем удалять размер`);
  }
  const withHistory = variantsWithHistory(db, removed.map((v) => v.id));
  const now = Date.now();
  for (const v of removed) {
    if (withHistory.has(v.id)) db.update(productVariants).set({ archived: true, updatedAt: now }).where(eq(productVariants.id, v.id)).run();
    else db.delete(productVariants).where(eq(productVariants.id, v.id)).run();
  }
  for (const v of removed) {
    if (withHistory.has(v.id)) archivedByName.set(normalizeSearchTerm(v.name), v.id);
  }
  sizes.forEach(({ id, initialQuantity, ...fields }, position) => {
    // A size added back under a name it had before reuses that row, so its history stays with one size.
    const revivedId = id == null ? archivedByName.get(normalizeSearchTerm(fields.name)) : undefined;
    if (revivedId !== undefined) archivedByName.delete(normalizeSearchTerm(fields.name));
    const rowId = id ?? revivedId;
    if (rowId == null) {
      insertSize(db, product.id, { ...fields, initialQuantity }, position, employeeId, 'Начальный остаток');
      return;
    }
    db.update(productVariants).set({ ...fields, archived: false, position, updatedAt: now }).where(eq(productVariants.id, rowId)).run();
    if (revivedId !== undefined && initialQuantity > 0) {
      applyMovement(db, { productId: product.id, variantId: revivedId, delta: initialQuantity, type: 'receipt', note: 'Начальный остаток', employeeId });
    }
  });
}

/** Archived sizes of the product by normalized name (the newest one wins). */
function archivedSizesByName(db: DbOrTx, productId: number): Map<string, number> {
  const rows = db
    .select({ id: productVariants.id, name: productVariants.name })
    .from(productVariants)
    .where(and(eq(productVariants.productId, productId), eq(productVariants.archived, true)))
    .orderBy(asc(productVariants.id))
    .all();
  return new Map(rows.map((r) => [normalizeSearchTerm(r.name), r.id]));
}

/**
 * Older builds send `size` and `minQuantity` of the product's only size. With several sizes they cannot be split, so
 * a changed value is refused; the unchanged ones those builds always resend are ignored.
 */
function applyLegacySize(db: DbOrTx, product: ProductRow, input: ProductFields): void {
  if (input.size === undefined && input.minQuantity === undefined) return;
  const sizes = currentVariants(db, product.id);
  const only = sizes.length === 1 ? sizes[0]! : null;
  if (only) {
    db.update(productVariants)
      .set({
        name: input.size === undefined ? only.name : (input.size ?? ''),
        minQuantity: input.minQuantity ?? only.minQuantity,
        updatedAt: Date.now(),
      })
      .where(eq(productVariants.id, only.id))
      .run();
    return;
  }
  const names = sizes.map((v) => v.name.trim()).filter(Boolean);
  const sizeChanged = input.size !== undefined && (input.size ?? null) !== (names.length ? names.join(', ') : null);
  const minChanged = input.minQuantity !== undefined && input.minQuantity !== sizes.reduce((sum, v) => sum + v.minQuantity, 0);
  if (sizeChanged || minChanged) {
    throw conflict(`У «${product.name}» несколько размеров — обновите приложение MIKAN, чтобы изменить их`);
  }
}

export function updateProduct(db: DbOrTx, id: number, input: ProductFields, employeeId: number): ProductRow {
  return db.transaction((tx) => {
    const current = getProductRow(tx, id);
    const kind = input.kind ?? current.kind;
    if (input.variants) syncSizes(tx, current, kind, input.variants, employeeId);
    else applyLegacySize(tx, current, input);
    const sizes = currentVariants(tx, id);
    if (kind === 'consumable' && sizes.length > 1) throw badRequest(CONSUMABLE_ONE_SIZE);
    const serviceIds = input.serviceIds === undefined ? undefined : checkServiceIds(tx, input.serviceIds);
    const photos = nextPhotos(current, input);

    const pick = <K extends keyof ProductFields & keyof ProductRow>(k: K) =>
      (input[k] === undefined ? current[k] : input[k]) as ProductRow[K];
    // A product moved to another section takes its category name along.
    const categoryName = input.category === undefined ? current.category : input.category;
    const stock = sizes.reduce((sum, v) => sum + v.quantity, 0);
    const base = {
      name: input.name ?? current.name,
      sku: pick('sku'),
      category: resolveCategory(tx, productScope(kind), categoryName),
      material: pick('material'),
      color: pick('color'),
      stone: pick('stone'),
      supplier: pick('supplier'),
    };
    const row = tx
      .update(products)
      .set({
        ...base,
        ...productSearchFields(base, sizes),
        ...(photos ? photoColumns(photos) : {}),
        kind,
        ...stockModeFields(kind, input, { stockMode: current.stockMode, presenceStatus: current.presenceStatus, quantity: stock }),
        threadType: pick('threadType'),
        thicknessMm: pick('thicknessMm'),
        description: pick('description'),
        price: input.price ?? current.price,
        cost: pick('cost'),
        unit: input.unit ?? current.unit,
        active: input.active ?? current.active,
        updatedAt: Date.now(),
      })
      .where(eq(products.id, id))
      .returning()
      .get();
    if (serviceIds) writeServiceLinks(tx, id, serviceIds);
    return row;
  });
}
