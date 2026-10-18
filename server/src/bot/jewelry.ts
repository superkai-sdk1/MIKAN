import { and, asc, eq, inArray } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { products, services } from '../db/schema.js';
import { serviceIdsByProduct, variantsByProduct } from '../domain/products.js';
import { formatThickness, threadLabel } from '../lib/jewelry.js';
import type { ProductRow, ServiceRow, VariantRow } from '../lib/serialize.js';
import { formatRub, searchKey } from '../lib/text.js';

/**
 * What the bot may say about jewelry in stock: the sizes that have stock and their prices — never how many are left.
 * `sizes` are the product's current sizes with stock, in order.
 */
function sizePrices(p: ProductRow, sizes: VariantRow[]) {
  const named = sizes.filter((v) => v.name.trim());
  const prices = sizes.map((v) => v.price ?? p.price);
  const min = prices.length ? Math.min(...prices) : p.price;
  return { named, min, differ: prices.some((price) => price !== min) };
}

const sizeList = (p: ProductRow, named: VariantRow[], withPrices: boolean) =>
  named.map((v) => (withPrices ? `${v.name.trim()} — ${formatRub(v.price ?? p.price)}` : v.name.trim())).join(', ');

/** «размеры в наличии: 6 мм, 8 мм · 1 500 ₽» (prices per size when they differ), just the price without sizes. */
export function offerText(p: ProductRow, sizes: VariantRow[]): string {
  const { named, min, differ } = sizePrices(p, sizes);
  if (named.length === 0) return formatRub(min);
  if (differ) return `размеры в наличии: ${sizeList(p, named, true)}`;
  return `размеры в наличии: ${sizeList(p, named, false)} · ${formatRub(min)}`;
}

/** The «Украшения в наличии» lines of the AI context; `services` — the active catalog, to name suitable zones. */
export function jewelryLines(db: DbOrTx, rows: ProductRow[], services: ServiceRow[]): string[] {
  const ids = rows.map((r) => r.id);
  const inStock = variantsByProduct(db, ids, { inStockOnly: true });
  const links = serviceIdsByProduct(db, ids);
  const serviceNames = new Map(services.map((s) => [s.id, s.name]));
  return rows.map((p) => {
    const suits = (links.get(p.id) ?? []).map((id) => serviceNames.get(id)).filter(Boolean);
    return [
      `• [id ${p.id}] ${p.name}`,
      p.category,
      p.material,
      threadLabel(p.threadType),
      p.thicknessMm != null ? formatThickness(p.thicknessMm) : null,
      p.color,
      p.stone,
      suits.length ? `подходит для: ${suits.join(', ')}` : null,
      offerText(p, inStock.get(p.id) ?? []),
      p.photoUrl ? 'есть фото' : null,
      p.description?.trim(),
    ]
      .filter(Boolean)
      .join(' · ');
  });
}

/**
 * Photo caption: «Лабрет · Титан ASTM F136 · 1.2 мм (16G) — 1 500 ₽» («от …» when sizes differ in price), then the
 * sizes in stock.
 */
export function productCaption(p: ProductRow, sizes: VariantRow[]): string {
  const { named, min, differ } = sizePrices(p, sizes);
  const title = [p.name, p.material, p.thicknessMm != null ? formatThickness(p.thicknessMm) : null].filter(Boolean).join(' · ');
  const head = `${title} — ${differ ? 'от ' : ''}${formatRub(min)}`;
  return named.length ? `${head}\nРазмеры в наличии: ${sizeList(p, named, differ)}` : head;
}

/** Current sizes of the product that have stock (what the caption may name). */
export function sizesInStock(db: DbOrTx, productId: number): VariantRow[] {
  return variantsByProduct(db, [productId], { inStockOnly: true }).get(productId) ?? [];
}

/** A product found by `find_jewelry`, with the sizes that have stock (empty — out of stock). */
export interface JewelryMatch {
  product: ProductRow;
  inStock: VariantRow[];
}

/** Russian word → a loose stem («лабреты» → «лабре», «кольца» → «коль»), so plural and case forms still match. */
function stem(word: string): string {
  if (/^\d/.test(word)) return word;
  if (word.length > 5) return word.slice(0, word.length - 2);
  if (word.length > 4) return word.slice(0, -1);
  return word;
}

const WORD_SPLIT = /[^\p{L}\p{N}.]+/u;

function queryWords(query: string): string[] {
  return [...new Set(searchKey(query).split(WORD_SPLIT).filter((w) => w.length >= 3 || /^\d/.test(w)).map(stem))];
}

/**
 * Active jewelry and goods matching a free-text query (name, category, material, colour, stone, sizes, thickness,
 * suitable zones, description): pieces matching every word first, else the best partial matches; pieces in stock
 * before sold-out ones.
 */
export function searchJewelry(db: DbOrTx, query: string, limit: number): JewelryMatch[] {
  const words = queryWords(query);
  if (words.length === 0) return [];
  const rows = db
    .select()
    .from(products)
    .where(and(inArray(products.kind, ['jewelry', 'goods']), eq(products.active, true)))
    .orderBy(asc(products.categorySort), asc(products.nameSort), asc(products.id))
    .all();
  const links = serviceIdsByProduct(db, rows.map((r) => r.id));
  const serviceNames = new Map(db.select({ id: services.id, name: services.name }).from(services).all().map((s) => [s.id, s.name]));
  const scored = rows
    .map((product) => {
      const haystack = searchKey(
        product.searchText,
        product.description,
        product.thicknessMm != null ? formatThickness(product.thicknessMm) : null,
        threadLabel(product.threadType),
        ...(links.get(product.id) ?? []).map((id) => serviceNames.get(id)),
      );
      const tokens = haystack.split(WORD_SPLIT);
      const score = words.filter((w) => (/^\d/.test(w) ? tokens.includes(w) : haystack.includes(w))).length;
      return { product, score };
    })
    .filter((x) => x.score > 0);
  const best = Math.max(0, ...scored.map((x) => x.score));
  const kept = best === words.length ? scored.filter((x) => x.score === best) : scored;
  const inStock = variantsByProduct(db, kept.map((x) => x.product.id), { inStockOnly: true });
  return kept
    .map((x) => ({ product: x.product, inStock: inStock.get(x.product.id) ?? [], score: x.score }))
    .sort((a, b) => b.score - a.score || Number(b.inStock.length > 0) - Number(a.inStock.length > 0))
    .slice(0, limit)
    .map(({ product, inStock: sizes }) => ({ product, inStock: sizes }));
}
