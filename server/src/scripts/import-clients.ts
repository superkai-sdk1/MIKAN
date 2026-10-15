/**
 * Bulk client import from a JSON file (e.g. a converted YCLIENTS export).
 *
 *   node dist/scripts/import-clients.js <records.json> [--apply] [--source=yclients]
 *
 * Without --apply it is a dry run. Re-running is safe: clients whose phone already exists are skipped,
 * and phone-less ones are matched by name + source + notes. Output contains counts only — no personal data.
 */
import { and, eq, isNull } from 'drizzle-orm';
import { z } from 'zod';
import type { Db, DbOrTx } from '../db/client.js';
import { clients } from '../db/schema.js';
import { createClient, findClientByPhone } from '../domain/clients.js';
import { calendarDate, instant, nullableText, phoneInput, requiredText } from '../lib/validation.js';
import { isEntryPoint, runImportCli, type ImportOptions } from './cli.js';

const recordSchema = z.object({
  name: requiredText(200),
  phone: phoneInput,
  birthday: calendarDate,
  notes: nullableText(2000),
  createdAt: instant.nullish(),
});

export type ImportRecord = z.input<typeof recordSchema>;

export interface ImportSummary {
  total: number;
  created: number;
  existing: number;
  duplicateInFile: number;
  invalid: Array<{ index: number; error: string }>;
}

function existingWithoutPhone(db: DbOrTx, name: string, source: string, notes: string | null): boolean {
  const notesMatch = notes === null ? isNull(clients.notes) : eq(clients.notes, notes);
  const row = db
    .select({ id: clients.id })
    .from(clients)
    .where(and(isNull(clients.phone), eq(clients.name, name), eq(clients.source, source), notesMatch))
    .get();
  return row !== undefined;
}

/** Validates and inserts the records in one transaction; with `apply: false` nothing is written. */
export function importClients(db: Db, records: unknown[], opts: ImportOptions): ImportSummary {
  const summary: ImportSummary = { total: records.length, created: 0, existing: 0, duplicateInFile: 0, invalid: [] };
  const seenPhones = new Set<string>();

  db.transaction((tx) => {
    records.forEach((raw, index) => {
      const parsed = recordSchema.safeParse(raw);
      if (!parsed.success) {
        summary.invalid.push({ index, error: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ') });
        return;
      }
      const record = parsed.data;
      const phone = record.phone ?? null;
      const notes = record.notes ?? null;

      if (phone && seenPhones.has(phone)) {
        summary.duplicateInFile += 1;
        return;
      }
      if (phone) seenPhones.add(phone);

      const exists = phone ? findClientByPhone(tx, phone) !== null : existingWithoutPhone(tx, record.name, opts.source, notes);
      if (exists) {
        summary.existing += 1;
        return;
      }

      summary.created += 1;
      if (!opts.apply) return;
      const row = createClient(tx, { name: record.name, phone, birthday: record.birthday ?? null, notes, source: opts.source });
      if (record.createdAt != null) {
        tx.update(clients).set({ createdAt: record.createdAt }).where(eq(clients.id, row.id)).run();
      }
    });
  });

  return summary;
}

if (isEntryPoint(import.meta.url)) runImportCli('import-clients', importClients);
