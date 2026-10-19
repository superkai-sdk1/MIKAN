/**
 * Off-site backups by hand (the server uploads every daily backup by itself once configured):
 *
 *   node dist/scripts/offsite-backup.js keygen              — a new BACKUP_ENCRYPTION_KEY (keep a copy outside the server!)
 *   node dist/scripts/offsite-backup.js upload [file]       — upload a backup now (default: the newest one) to check the setup
 *   node dist/scripts/offsite-backup.js decrypt <in> <out>  — decrypt a downloaded `.db.enc` copy back into a SQLite file
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { loadConfig } from '../config.js';
import { decryptBackup, uploadBackupOffsite } from '../domain/offsite-backup.js';
import { errorMessage } from '../lib/errors.js';
import { isEntryPoint } from './cli.js';

const USAGE = 'Usage: node dist/scripts/offsite-backup.js keygen | upload [file] | decrypt <in.db.enc> <out.db>\n';
const KEY_BYTES = 32;

/** The newest daily backup in `dir` (names sort by date), or null. */
export function newestBackup(dir: string): string | null {
  if (!fs.existsSync(dir)) return null;
  const files = fs
    .readdirSync(dir)
    .filter((f) => /^mikan-\d{4}-\d{2}-\d{2}\.db$/.test(f))
    .sort();
  const last = files.at(-1);
  return last ? path.join(dir, last) : null;
}

function decrypt(input: string, output: string): number {
  const key = Buffer.from(process.env.BACKUP_ENCRYPTION_KEY ?? '', 'base64');
  if (key.length !== KEY_BYTES) {
    process.stderr.write('BACKUP_ENCRYPTION_KEY: нужен ключ из 32 байт в base64\n');
    return 2;
  }
  fs.writeFileSync(output, decryptBackup(fs.readFileSync(input), key));
  process.stdout.write(`Расшифровано: ${output}\n`);
  return 0;
}

async function upload(file: string | undefined): Promise<number> {
  const config = loadConfig();
  if (!config.offsiteBackup) {
    const problem = config.offsiteBackupProblem ? `: ${config.offsiteBackupProblem}` : '';
    process.stderr.write(`Бэкапы вне сервера не настроены${problem}\n`);
    return 2;
  }
  const source = file ?? newestBackup(path.join(config.dataDir, 'backups'));
  if (!source) {
    process.stderr.write('Нет локальных бэкапов для выгрузки\n');
    return 2;
  }
  const result = await uploadBackupOffsite(config.offsiteBackup, source);
  process.stdout.write(`${JSON.stringify({ uploaded: result.key, bytes: result.bytes, pruned: result.pruned }, null, 2)}\n`);
  return 0;
}

async function main(args: string[]): Promise<number> {
  const [command, ...rest] = args;
  if (command === 'keygen') {
    process.stdout.write(`${crypto.randomBytes(KEY_BYTES).toString('base64')}\n`);
    return 0;
  }
  if (command === 'decrypt' && rest.length === 2) return decrypt(rest[0]!, rest[1]!);
  if (command === 'upload' && rest.length <= 1) return upload(rest[0]);
  process.stderr.write(USAGE);
  return 2;
}

if (isEntryPoint(import.meta.url)) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (err) => {
      process.stderr.write(`${errorMessage(err)}\n`);
      process.exit(1);
    },
  );
}
