const MIN_DIGITS = 5;
const MAX_DIGITS = 15;

/**
 * Normalizes a phone number per the API contract:
 * Russian numbers (8XXXXXXXXXX, 7XXXXXXXXXX, +7 (XXX) XXX-XX-XX, 9XXXXXXXXX) → +7XXXXXXXXXX;
 * anything else → "+" followed by its digits. Returns null when there are no digits.
 */
export function normalizePhone(input: string | null | undefined): string | null {
  if (input == null) return null;
  const digits = input.replace(/\D/g, '');
  if (digits.length === 0) return null;
  if (digits.length === 11 && (digits.startsWith('8') || digits.startsWith('7'))) {
    return `+7${digits.slice(1)}`;
  }
  if (digits.length === 10 && digits.startsWith('9')) return `+7${digits}`;
  return `+${digits}`;
}

export function isPlausiblePhone(normalized: string): boolean {
  const digits = normalized.replace(/\D/g, '');
  return digits.length >= MIN_DIGITS && digits.length <= MAX_DIGITS;
}

/** Digit variants used for search: "79991234567 89991234567 9991234567" for Russian numbers. */
export function phoneSearchVariants(normalized: string | null): string {
  if (!normalized) return '';
  const digits = normalized.replace(/\D/g, '');
  if (digits.length === 11 && digits.startsWith('7')) {
    const local = digits.slice(1);
    return `${digits} 8${local} ${local}`;
  }
  return digits;
}
