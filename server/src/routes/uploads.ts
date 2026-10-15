import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import type { FastifyInstance } from 'fastify';
import { uploadsDir } from '../app.js';
import type { AppContext } from '../context.js';
import { badRequest } from '../lib/errors.js';

const EXTENSION_BY_MIME: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'image/heif': 'heic',
};

/** Checks the file signature so a renamed non-image cannot be uploaded. */
export function sniffImage(buf: Buffer): 'jpg' | 'png' | 'webp' | 'heic' | null {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpg';
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  if (buf.length >= 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') return 'webp';
  if (buf.length >= 12 && buf.toString('ascii', 4, 8) === 'ftyp') {
    const brand = buf.toString('ascii', 8, 12);
    if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1', 'heim', 'heis'].includes(brand)) return 'heic';
  }
  return null;
}

export function uploadRoutes(app: FastifyInstance, ctx: AppContext): void {
  app.post('/uploads', async (request) => {
    if (!request.isMultipart()) throw badRequest('Отправьте файл в формате multipart/form-data (поле file)');
    const file = await request.file();
    if (!file || file.fieldname !== 'file') throw badRequest('Файл не найден: используйте поле «file»');
    const declared = EXTENSION_BY_MIME[file.mimetype.toLowerCase()];
    if (!declared) throw badRequest('Поддерживаются только изображения JPEG, PNG, HEIC и WebP');
    const buffer = await file.toBuffer();
    if (file.file.truncated) throw badRequest('Файл слишком большой (максимум 10 МБ)');
    const actual = sniffImage(buffer);
    if (!actual) throw badRequest('Файл повреждён или не является изображением JPEG, PNG, HEIC или WebP');
    const name = `${randomUUID()}.${actual}`;
    await fs.writeFile(path.join(uploadsDir(ctx), name), buffer, { mode: 0o644 });
    request.log.info({ name, bytes: buffer.length }, 'upload stored');
    return { url: `/uploads/${name}` };
  });
}
