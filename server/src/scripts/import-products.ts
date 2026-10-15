/**
 * Bulk product import (jewelry or consumables) from a JSON file, e.g. a converted YCLIENTS goods export.
 *
 *   node dist/scripts/import-products.js <records.json> [--apply]
 *
 * Without --apply it is a dry run. Re-running is safe: a product with the same kind + name + category is skipped.
 */
import { and, eq, isNull } from 'drizzle-orm';
import { z } from 'zod';
import type { Db, DbOrTx } from '../db/client.js';
import { products } from '../db/schema.js';
import { createProduct } from '../domain/products.js';
import { money, nullableText, requiredText } from '../lib/validation.js';
import { isEntryPoint, runImportCli, type ImportOptions } from './cli.js';

const quantity = z.number().int().min(0).max(1_000_000);

const recordSchema = z.object({
  kind: z.enum(['jewelry', 'consumable']),
  name: requiredText(200),
  category: nullableText(100),
  description: nullableText(5000),
  unit: requiredText(20).default('шт'),
  minQuantity: quantity.default(0),
  price: money.default(0),
  cost: money.nullish(),
  initialQuantity: quantity.default(0),
});

export type ProductImportRecord = z.input<typeof recordSchema>;

export interface ProductImportSummary {
  total: number;
  created: number;
  existing: number;
  invalid: Array<{ index: number; error: string }>;
}

function productExists(db: DbOrTx, kind: 'jewelry' | 'consumable', name: string, category: string | null): boolean {
  const categoryMatch = category === null ? isNull(products.category) : eq(products.category, category);
  const row = db
    .select({ id: products.id })
    .from(products)
    .where(and(eq(products.kind, kind), eq(products.name, name), categoryMatch))
    .get();
  return row !== undefined;
}

/** Validates and inserts the products in one transaction; with `apply: false` nothing is written. */
export function importProducts(db: Db, records: unknown[], opts: ImportOptions): ProductImportSummary {
  const summary: ProductImportSummary = { total: records.length, created: 0, existing: 0, invalid: [] };
  const seen = new Set<string>();

  db.transaction((tx) => {
    records.forEach((raw, index) => {
      const parsed = recordSchema.safeParse(raw);
      if (!parsed.success) {
        summary.invalid.push({ index, error: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ') });
        return;
      }
      const record = { ...parsed.data, category: parsed.data.category ?? null };
      const key = `${record.kind}\u0000${record.name}\u0000${record.category ?? ''}`;
      if (seen.has(key) || productExists(tx, record.kind, record.name, record.category)) {
        summary.existing += 1;
        return;
      }
      seen.add(key);

      summary.created += 1;
      if (opts.apply) createProduct(tx, record, null, `Начальный остаток (импорт ${opts.source})`);
    });
  });

  return summary;
}

if (isEntryPoint(import.meta.url)) runImportCli('import-products', importProducts);
