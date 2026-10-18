import { and, asc, count, eq, isNotNull, max } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { catalogCategories, products, services } from '../db/schema.js';
import { badRequest, conflict, notFound } from '../lib/errors.js';
import { normalizeSearchTerm } from '../lib/text.js';
import { refreshProductSearch } from './product-search.js';

/** Warehouse sections; product sections are product kinds. */
export const CATALOG_SECTIONS = ['jewelry', 'goods', 'consumable', 'service'] as const;
export type CatalogSection = (typeof CATALOG_SECTIONS)[number];
export const SERVICE_CATEGORIES = ['tattoo', 'piercing', 'other'] as const;

type CategoryRow = typeof catalogCategories.$inferSelect;

/** Categories live per section, and per service category in the `service` section ('' for product sections). */
export interface CategoryScope {
  section: CatalogSection;
  serviceCategory: string;
}

export const productScope = (kind: string): CategoryScope => ({ section: kind as CatalogSection, serviceCategory: '' });
export const serviceScope = (category: string): CategoryScope => ({ section: 'service', serviceCategory: category });

const sameScope = (a: CategoryScope, b: CategoryScope) => a.section === b.section && a.serviceCategory === b.serviceCategory;
const scopeOf = (row: CategoryRow): CategoryScope => ({ section: row.section as CatalogSection, serviceCategory: row.serviceCategory });

function scopeRows(db: DbOrTx, scope: CategoryScope): CategoryRow[] {
  return db
    .select()
    .from(catalogCategories)
    .where(and(eq(catalogCategories.section, scope.section), eq(catalogCategories.serviceCategory, scope.serviceCategory)))
    .orderBy(asc(catalogCategories.position), asc(catalogCategories.id))
    .all();
}

function insertCategory(db: DbOrTx, scope: CategoryScope, name: string): CategoryRow {
  const last = db
    .select({ position: max(catalogCategories.position) })
    .from(catalogCategories)
    .where(and(eq(catalogCategories.section, scope.section), eq(catalogCategories.serviceCategory, scope.serviceCategory)))
    .get()?.position;
  const now = Date.now();
  return db
    .insert(catalogCategories)
    .values({ ...scope, name, position: last == null ? 0 : last + 1, createdAt: now, updatedAt: now })
    .returning()
    .get();
}

/**
 * The stored spelling of a category name: an existing category of the scope that matches it (case- and «ё»-insensitive),
 * else a new category at the end. Blank → null (no category).
 */
export function resolveCategory(db: DbOrTx, scope: CategoryScope, name: string | null | undefined): string | null {
  const trimmed = name?.trim();
  if (!trimmed) return null;
  const key = normalizeSearchTerm(trimmed);
  const existing = scopeRows(db, scope).find((row) => normalizeSearchTerm(row.name) === key);
  return (existing ?? insertCategory(db, scope, trimmed)).name;
}

/** Registers category names items carry that the registry does not know (rows written by imports or older code). */
function registerMissing(db: DbOrTx): void {
  const known = new Set(db.select().from(catalogCategories).all().map((r) => `${r.section}\u0000${r.serviceCategory}\u0000${r.name}`));
  const used = [
    ...db
      .selectDistinct({ section: products.kind, name: products.category })
      .from(products)
      .where(isNotNull(products.category))
      .all()
      .map((r) => ({ scope: productScope(r.section), name: r.name! })),
    ...db
      .selectDistinct({ category: services.category, name: services.groupName })
      .from(services)
      .where(isNotNull(services.groupName))
      .all()
      .map((r) => ({ scope: serviceScope(r.category), name: r.name! })),
  ];
  for (const { scope, name } of used) {
    const key = `${scope.section}\u0000${scope.serviceCategory}\u0000${name}`;
    if (known.has(key) || !name.trim()) continue;
    insertCategory(db, scope, name);
    known.add(key);
  }
}

/** Items per category name within each scope. */
function itemCounts(db: DbOrTx): Map<string, number> {
  const counts = new Map<string, number>();
  for (const r of db
    .select({ kind: products.kind, name: products.category, n: count() })
    .from(products)
    .where(isNotNull(products.category))
    .groupBy(products.kind, products.category)
    .all()) {
    counts.set(`${r.kind}\u0000\u0000${r.name}`, r.n);
  }
  for (const r of db
    .select({ category: services.category, name: services.groupName, n: count() })
    .from(services)
    .where(isNotNull(services.groupName))
    .groupBy(services.category, services.groupName)
    .all()) {
    counts.set(`service\u0000${r.category}\u0000${r.name}`, r.n);
  }
  return counts;
}

export const categoryOut = (row: CategoryRow, itemCount: number) => ({
  id: row.id,
  section: row.section,
  serviceCategory: row.section === 'service' ? row.serviceCategory : null,
  name: row.name,
  position: row.position,
  itemCount,
});
export type CategoryOut = ReturnType<typeof categoryOut>;

export function listCategories(db: DbOrTx, section?: CatalogSection): CategoryOut[] {
  registerMissing(db);
  const counts = itemCounts(db);
  return db
    .select()
    .from(catalogCategories)
    .where(section ? eq(catalogCategories.section, section) : undefined)
    .orderBy(asc(catalogCategories.section), asc(catalogCategories.serviceCategory), asc(catalogCategories.position), asc(catalogCategories.id))
    .all()
    .map((row) => categoryOut(row, counts.get(`${row.section}\u0000${row.serviceCategory}\u0000${row.name}`) ?? 0));
}

export function getCategoryRow(db: DbOrTx, id: number): CategoryRow {
  const row = db.select().from(catalogCategories).where(eq(catalogCategories.id, id)).get();
  if (!row) throw notFound('Категория не найдена');
  return row;
}

function serializeOne(db: DbOrTx, row: CategoryRow): CategoryOut {
  return listCategories(db, row.section as CatalogSection).find((c) => c.id === row.id) ?? categoryOut(row, 0);
}

function assertNameFree(db: DbOrTx, scope: CategoryScope, name: string, exceptId?: number): void {
  const key = normalizeSearchTerm(name);
  const taken = scopeRows(db, scope).find((row) => row.id !== exceptId && normalizeSearchTerm(row.name) === key);
  if (taken) throw conflict(`Категория «${taken.name}» уже есть`);
}

export function scopeFor(section: CatalogSection, serviceCategory: string | null | undefined): CategoryScope {
  if (section === 'service') {
    if (!serviceCategory || !(SERVICE_CATEGORIES as readonly string[]).includes(serviceCategory)) {
      throw badRequest('«Раздел услуг»: укажите тату, пирсинг или другое');
    }
    return serviceScope(serviceCategory);
  }
  if (serviceCategory) throw badRequest('Раздел услуг указывается только для категорий услуг');
  return productScope(section);
}

export function createCategory(db: DbOrTx, scope: CategoryScope, name: string): CategoryOut {
  return db.transaction((tx) => {
    registerMissing(tx);
    assertNameFree(tx, scope, name);
    return serializeOne(tx, insertCategory(tx, scope, name.trim()));
  });
}

/** Renames the category and every item in it. */
function moveItems(db: DbOrTx, scope: CategoryScope, from: string, to: string | null): void {
  if (scope.section === 'service') {
    db.update(services)
      .set({ groupName: to, updatedAt: Date.now() })
      .where(and(eq(services.category, scope.serviceCategory), eq(services.groupName, from)))
      .run();
    return;
  }
  const moved = db
    .update(products)
    .set({ category: to, updatedAt: Date.now() })
    .where(and(eq(products.kind, scope.section), eq(products.category, from)))
    .returning({ id: products.id })
    .all();
  for (const { id } of moved) refreshProductSearch(db, id);
}

export function renameCategory(db: DbOrTx, id: number, name: string): CategoryOut {
  return db.transaction((tx) => {
    registerMissing(tx);
    const row = getCategoryRow(tx, id);
    const scope = scopeOf(row);
    const next = name.trim();
    assertNameFree(tx, scope, next, row.id);
    if (next !== row.name) {
      tx.update(catalogCategories).set({ name: next, updatedAt: Date.now() }).where(eq(catalogCategories.id, id)).run();
      moveItems(tx, scope, row.name, next);
    }
    return serializeOne(tx, getCategoryRow(tx, id));
  });
}

/** Positions 0… in the given order; every category of one scope must be listed. */
export function orderCategories(db: DbOrTx, ids: number[]): CategoryOut[] {
  return db.transaction((tx) => {
    registerMissing(tx);
    if (new Set(ids).size !== ids.length) throw badRequest('Категория указана дважды');
    const rows = ids.map((id) => getCategoryRow(tx, id));
    const scope = scopeOf(rows[0]!);
    if (rows.some((row) => !sameScope(scopeOf(row), scope))) throw badRequest('Категории из разных разделов');
    if (scopeRows(tx, scope).length !== rows.length) throw badRequest('Перечислите все категории раздела');
    const now = Date.now();
    rows.forEach((row, position) => {
      tx.update(catalogCategories).set({ position, updatedAt: now }).where(eq(catalogCategories.id, row.id)).run();
    });
    return listCategories(tx, scope.section).filter((c) => (c.serviceCategory ?? '') === scope.serviceCategory);
  });
}

function compactPositions(db: DbOrTx, scope: CategoryScope): void {
  scopeRows(db, scope).forEach((row, position) => {
    if (row.position !== position) db.update(catalogCategories).set({ position }).where(eq(catalogCategories.id, row.id)).run();
  });
}

export function mergeCategory(db: DbOrTx, id: number, intoId: number): CategoryOut {
  return db.transaction((tx) => {
    registerMissing(tx);
    if (id === intoId) throw badRequest('Нельзя объединить категорию саму с собой');
    const source = getCategoryRow(tx, id);
    const target = getCategoryRow(tx, intoId);
    const scope = scopeOf(source);
    if (!sameScope(scope, scopeOf(target))) throw badRequest('Объединять можно только категории одного раздела');
    moveItems(tx, scope, source.name, target.name);
    tx.delete(catalogCategories).where(eq(catalogCategories.id, id)).run();
    compactPositions(tx, scope);
    return serializeOne(tx, getCategoryRow(tx, intoId));
  });
}

export function deleteCategory(db: DbOrTx, id: number): void {
  db.transaction((tx) => {
    registerMissing(tx);
    const row = getCategoryRow(tx, id);
    const scope = scopeOf(row);
    moveItems(tx, scope, row.name, null);
    tx.delete(catalogCategories).where(eq(catalogCategories.id, id)).run();
    compactPositions(tx, scope);
  });
}
