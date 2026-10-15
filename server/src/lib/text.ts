export const TELEGRAM_MAX_MESSAGE = 4096;
export const TELEGRAM_MAX_CAPTION = 1024;

/** Lowercased, whitespace-collapsed search key built from the given parts (JS lowercasing handles Cyrillic). */
export function searchKey(...parts: Array<string | null | undefined>): string {
  return parts
    .filter((p): p is string => typeof p === 'string' && p.length > 0)
    .join(' ')
    .toLowerCase()
    .replace(/ё/g, 'е')
    .replace(/\s+/g, ' ')
    .trim();
}

export function normalizeSearchTerm(term: string): string {
  return term.toLowerCase().replace(/ё/g, 'е').replace(/\s+/g, ' ').trim();
}

/**
 * Splits text into chunks of at most `limit` characters, preferring paragraph,
 * then line, then sentence/word boundaries.
 */
export function splitMessage(text: string, limit = TELEGRAM_MAX_MESSAGE): string[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) return [];
  const chunks: string[] = [];
  let rest = trimmed;
  while (rest.length > limit) {
    const window = rest.slice(0, limit);
    const cut = findCut(window);
    chunks.push(rest.slice(0, cut).trimEnd());
    rest = rest.slice(cut).trimStart();
  }
  if (rest.length > 0) chunks.push(rest);
  return chunks;
}

function findCut(window: string): number {
  const minCut = Math.floor(window.length * 0.5);
  for (const sep of ['\n\n', '\n', '. ', ' ']) {
    const at = window.lastIndexOf(sep);
    if (at >= minCut) return at + sep.length;
  }
  return window.length;
}

export function truncate(text: string, max: number): string {
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`;
}

export function formatRub(amount: number): string {
  return `${amount.toLocaleString('ru-RU').replace(/ /g, ' ')} ₽`;
}
