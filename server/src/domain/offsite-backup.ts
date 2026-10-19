import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import type { OffsiteBackupConfig } from '../config.js';
import { deleteObject, listKeys, putObject, type Fetch } from '../lib/s3.js';

/**
 * Off-site copies of the daily backup: the SQLite file encrypted with AES-256-GCM on the server (the storage never
 * sees client data), uploaded to S3-compatible storage, the newest `keep` copies kept.
 * File format: `MIKANBK1` (8 bytes) + IV (12) + GCM tag (16) + ciphertext.
 */

const MAGIC = Buffer.from('MIKANBK1');
const IV_BYTES = 12;
const TAG_BYTES = 16;
const COPY_RE = /mikan-\d{4}-\d{2}-\d{2}\.db\.enc$/;

export function encryptBackup(data: Buffer, key: Buffer): Buffer {
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const body = Buffer.concat([cipher.update(data), cipher.final()]);
  return Buffer.concat([MAGIC, iv, cipher.getAuthTag(), body]);
}

/** Throws on a wrong key or a damaged file (GCM checks the whole content). */
export function decryptBackup(blob: Buffer, key: Buffer): Buffer {
  if (blob.length < MAGIC.length + IV_BYTES + TAG_BYTES || !blob.subarray(0, MAGIC.length).equals(MAGIC)) {
    throw new Error('Это не зашифрованный бэкап MIKAN');
  }
  const iv = blob.subarray(MAGIC.length, MAGIC.length + IV_BYTES);
  const tag = blob.subarray(MAGIC.length + IV_BYTES, MAGIC.length + IV_BYTES + TAG_BYTES);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(blob.subarray(MAGIC.length + IV_BYTES + TAG_BYTES)), decipher.final()]);
}

export interface OffsiteResult {
  key: string;
  bytes: number;
  pruned: string[];
}

/** Encrypts and uploads one local backup, then deletes all but the newest `keep` copies under the prefix. */
export async function uploadBackupOffsite(
  config: OffsiteBackupConfig,
  file: string,
  fetchImpl?: Fetch,
  now = Date.now(),
): Promise<OffsiteResult> {
  const body = encryptBackup(fs.readFileSync(file), config.key);
  const key = `${config.prefix}${path.basename(file)}.enc`;
  await putObject(config.s3, key, body, fetchImpl, now);
  const copies = (await listKeys(config.s3, config.prefix, fetchImpl, now)).filter((k) => COPY_RE.test(k)).sort();
  const stale = copies.slice(0, Math.max(0, copies.length - config.keep));
  for (const old of stale) await deleteObject(config.s3, old, fetchImpl, now);
  return { key, bytes: body.length, pruned: stale };
}
