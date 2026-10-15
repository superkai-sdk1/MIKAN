/** Shared runner for the JSON import scripts: argument parsing, DB opening and a counts-only summary. */
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { openDatabase, type Db } from '../db/client.js';

export interface ImportOptions {
  apply: boolean;
  source: string;
}

/** True when the given module (`import.meta.url`) is the script node was started with. */
export function isEntryPoint(moduleUrl: string): boolean {
  return Boolean(process.argv[1]) && moduleUrl === pathToFileURL(process.argv[1]!).href;
}

/** Reads `<records.json> [--apply] [--source=…]`, runs `run` against DATA_DIR/mikan.db and prints its summary. */
export function runImportCli(scriptName: string, run: (db: Db, records: unknown[], opts: ImportOptions) => object): void {
  const args = process.argv.slice(2);
  const file = args.find((a) => !a.startsWith('--'));
  if (!file) {
    process.stderr.write(`Usage: node dist/scripts/${scriptName}.js <records.json> [--apply] [--source=yclients]\n`);
    process.exit(2);
  }
  const opts: ImportOptions = {
    apply: args.includes('--apply'),
    source: args.find((a) => a.startsWith('--source='))?.slice('--source='.length) || 'yclients',
  };

  const records: unknown = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!Array.isArray(records)) throw new Error('Ожидается JSON-массив записей');

  const { db, sqlite } = openDatabase(path.join(process.env.DATA_DIR ?? './data', 'mikan.db'));
  try {
    const summary = run(db, records, opts);
    process.stdout.write(`${JSON.stringify({ mode: opts.apply ? 'apply' : 'dry-run', ...summary }, null, 2)}\n`);
  } finally {
    sqlite.close();
  }
}
