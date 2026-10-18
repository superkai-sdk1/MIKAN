import type { DbOrTx } from '../db/client.js';
import { serviceIdsByProduct, variantsByProduct } from '../domain/products.js';
import { formatThickness, threadLabel } from '../lib/jewelry.js';
import type { ProductRow, ServiceRow, VariantRow } from '../lib/serialize.js';
import { formatRub } from '../lib/text.js';

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
