import fs from 'node:fs';
import path from 'node:path';
import { parsePhotos, parseVariants, type ServiceRow } from '../lib/serialize.js';
import { formatRub, formatServicePrice, TELEGRAM_MAX_CAPTION, truncate } from '../lib/text.js';
import type { PhotoSource } from './gateway.js';

/** Description length inside a service caption (the rest of the caption stays readable). */
const CAPTION_DESCRIPTION_MAX = 300;

/** Service card caption: name, price, variants and a short description (within Telegram's caption limit). */
export function serviceCaption(s: ServiceRow): string {
  const variants = parseVariants(s.variantsJson);
  const description = s.description?.trim();
  const lines = [
    s.name,
    formatServicePrice(s.price, s.priceMax, s.priceFrom),
    ...(variants.length ? ['Варианты:', ...variants.map((v) => `• ${v.name} — ${formatRub(v.price)}`)] : []),
    ...(description ? [truncate(description, CAPTION_DESCRIPTION_MAX)] : []),
  ];
  return truncate(lines.join('\n'), TELEGRAM_MAX_CAPTION);
}

/** Where to read an uploaded picture from; null when it can't be sent as a Telegram photo. */
export function photoSourceFor(dataDir: string, photoUrl: string | null): PhotoSource | null {
  if (!photoUrl || /\.hei[cf]$/i.test(photoUrl)) return null; // Telegram can't show HEIC as a photo
  if (/^https?:\/\//.test(photoUrl)) return { kind: 'url', url: photoUrl };
  if (!photoUrl.startsWith('/uploads/')) return null;
  const file = path.join(dataDir, 'uploads', path.basename(photoUrl));
  return fs.existsSync(file) ? { kind: 'file', path: file } : null;
}

/** The picture the bot sends for a service: the schematic cover, else the first photo of works. */
export function servicePhotoSource(dataDir: string, s: ServiceRow): PhotoSource | null {
  return photoSourceFor(dataDir, s.imageUrl) ?? photoSourceFor(dataDir, parsePhotos(s.photosJson)[0] ?? null);
}

/** Text stored in the chat history for a sent picture (also lets the bot see what it already showed). */
export const photoMessageText = (caption: string): string => `[Фото] ${caption}`;
