import { and, eq } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { products, productVariants } from '../db/schema.js';
import type { ProductRow, VariantRow } from '../lib/serialize.js';
import { searchKey } from '../lib/text.js';

type SearchSource = Pick<ProductRow, 'name' | 'sku' | 'category' | 'material' | 'color' | 'stone' | 'supplier'>;

/** Sort and search columns derived from the product's text fields and its current sizes. */
export function productSearchFields(p: SearchSource, sizes: Array<Pick<VariantRow, 'name' | 'sku'>>) {
  return {
    nameSort: searchKey(p.name),
    categorySort: searchKey(p.category),
    searchText: searchKey(p.name, p.sku, p.category, p.material, p.color, p.stone, p.supplier, ...sizes.flatMap((v) => [v.name, v.sku])),
  };
}

/** Recomputes the search columns after the set of current sizes changed outside the product editor. */
export function refreshProductSearch(db: DbOrTx, productId: number): void {
  const product = db.select().from(products).where(eq(products.id, productId)).get();
  if (!product) return;
  const sizes = db
    .select({ name: productVariants.name, sku: productVariants.sku })
    .from(productVariants)
    .where(and(eq(productVariants.productId, productId), eq(productVariants.archived, false)))
    .all();
  db.update(products).set(productSearchFields(product, sizes)).where(eq(products.id, productId)).run();
}
