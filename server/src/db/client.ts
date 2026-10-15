import { fileURLToPath } from 'node:url';
import Database from 'better-sqlite3';
import { drizzle, type BetterSQLite3Database } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';
import type { BaseSQLiteDatabase } from 'drizzle-orm/sqlite-core';
import * as schema from './schema.js';

export type Db = BetterSQLite3Database<typeof schema>;
/** Either the database or a transaction — everything here is synchronous (better-sqlite3). */
export type DbOrTx = BaseSQLiteDatabase<'sync', Database.RunResult, typeof schema>;
export type Sqlite = Database.Database;

export interface DbHandle {
  db: Db;
  sqlite: Sqlite;
}

/** `server/drizzle` — resolves the same from `src/db` (tsx/vitest) and `dist/db` (compiled). */
export const MIGRATIONS_DIR = fileURLToPath(new URL('../../drizzle', import.meta.url));

/**
 * Opens the SQLite database (file path or ':memory:'), enables WAL + foreign keys
 * and applies pending migrations.
 */
export function openDatabase(filename: string): DbHandle {
  const sqlite = new Database(filename);
  if (filename !== ':memory:') sqlite.pragma('journal_mode = WAL');
  sqlite.pragma('foreign_keys = ON');
  sqlite.pragma('busy_timeout = 5000');
  sqlite.pragma('synchronous = NORMAL');
  const db = drizzle(sqlite, { schema });
  migrate(db, { migrationsFolder: MIGRATIONS_DIR });
  return { db, sqlite };
}
