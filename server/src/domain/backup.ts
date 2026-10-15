import fs from 'node:fs';
import path from 'node:path';
import type { Sqlite } from '../db/client.js';
import { localDate, localHour } from '../lib/time.js';

export const BACKUP_KEEP = 14;
export const BACKUP_HOUR = 4;
const FILE_RE = /^mikan-(\d{4}-\d{2}-\d{2})\.db$/;

export function backupFileName(date: string): string {
  return `mikan-${date}.db`;
}

/** Deletes all but the newest `keep` backups (by date in the file name). Returns deleted names. */
export function pruneBackups(dir: string, keep = BACKUP_KEEP): string[] {
  if (!fs.existsSync(dir)) return [];
  const files = fs
    .readdirSync(dir)
    .filter((f) => FILE_RE.test(f))
    .sort()
    .reverse();
  const stale = files.slice(keep);
  for (const file of stale) fs.rmSync(path.join(dir, file), { force: true });
  return stale;
}

/**
 * Creates today's backup (studio-local date) once the studio clock has passed 04:00 and no
 * backup for today exists yet — so a server that was down at 04:00 still backs up later that day.
 * Returns the created file path, or null when nothing was due.
 */
export async function runBackupIfDue(sqlite: Sqlite, dir: string, tz: string, now = Date.now()): Promise<string | null> {
  if (localHour(now, tz) < BACKUP_HOUR) return null;
  const target = path.join(dir, backupFileName(localDate(now, tz)));
  if (fs.existsSync(target)) return null;
  fs.mkdirSync(dir, { recursive: true });
  const tmp = `${target}.part`;
  await sqlite.backup(tmp);
  fs.renameSync(tmp, target);
  pruneBackups(dir);
  return target;
}
