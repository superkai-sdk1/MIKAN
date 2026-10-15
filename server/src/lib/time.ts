import { DateTime, IANAZone } from 'luxon';

export const MINUTE_MS = 60_000;
export const HOUR_MS = 60 * MINUTE_MS;
export const DAY_MS = 24 * HOUR_MS;

export function nowMs(): number {
  return Date.now();
}

export function toIso(value: number): string;
export function toIso(value: number | null | undefined): string | null;
export function toIso(value: number | null | undefined): string | null {
  if (value == null) return null;
  return new Date(value).toISOString();
}

/** Parses an ISO 8601 instant; strings without an offset are interpreted as UTC. Returns ms or null. */
export function parseInstant(value: string): number | null {
  const dt = DateTime.fromISO(value.trim(), { zone: 'utc' });
  return dt.isValid ? dt.toMillis() : null;
}

export function isValidTimezone(tz: string): boolean {
  return IANAZone.isValidZone(tz);
}

/** Calendar date "YYYY-MM-DD" validity check. */
export function isValidCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  return DateTime.fromISO(value, { zone: 'utc' }).isValid;
}

export function localDate(ms: number, tz: string): string {
  return DateTime.fromMillis(ms, { zone: tz }).toISODate() ?? '';
}

/** [start, end) of the studio-local calendar day containing `ms`. */
export function localDayBounds(ms: number, tz: string): { start: number; end: number; date: string } {
  const start = DateTime.fromMillis(ms, { zone: tz }).startOf('day');
  return { start: start.toMillis(), end: start.plus({ days: 1 }).toMillis(), date: start.toISODate() ?? '' };
}

/** Every studio-local date touched by [from, to), inclusive of the day containing from and (to - 1ms). */
export function localDatesInRange(from: number, to: number, tz: string): string[] {
  const dates: string[] = [];
  if (to <= from) return dates;
  let cursor = DateTime.fromMillis(from, { zone: tz }).startOf('day');
  const last = DateTime.fromMillis(to - 1, { zone: tz }).startOf('day');
  while (cursor <= last) {
    dates.push(cursor.toISODate() ?? '');
    cursor = cursor.plus({ days: 1 });
  }
  return dates;
}

/**
 * Aftercare send time: dayOffset 0 → `completedAt + 5 min`;
 * N > 0 → studio-local date of completion + N days at `hour`:00 local time.
 */
export function aftercareSendAt(completedAt: number, dayOffset: number, hour: number, tz: string): number {
  if (dayOffset <= 0) return completedAt + 5 * MINUTE_MS;
  return DateTime.fromMillis(completedAt, { zone: tz })
    .startOf('day')
    .plus({ days: dayOffset })
    .set({ hour, minute: 0, second: 0, millisecond: 0 })
    .toMillis();
}

/** "четверг, 15 октября в 14:00" in the studio timezone. */
export function formatHumanDateTime(ms: number, tz: string): string {
  return DateTime.fromMillis(ms, { zone: tz }).setLocale('ru').toFormat("cccc, d MMMM 'в' HH:mm");
}

/** "15.10.2026 14:00" in the studio timezone. */
export function formatShortDateTime(ms: number, tz: string): string {
  return DateTime.fromMillis(ms, { zone: tz }).toFormat('dd.MM.yyyy HH:mm');
}

export function formatTime(ms: number, tz: string): string {
  return DateTime.fromMillis(ms, { zone: tz }).toFormat('HH:mm');
}

export function formatShortDate(ms: number, tz: string): string {
  return DateTime.fromMillis(ms, { zone: tz }).toFormat('dd.MM.yyyy');
}

/** Whole studio-local calendar days between two instants (b - a). */
export function localDaysBetween(a: number, b: number, tz: string): number {
  const da = DateTime.fromMillis(a, { zone: tz }).startOf('day');
  const db = DateTime.fromMillis(b, { zone: tz }).startOf('day');
  return Math.round(db.diff(da, 'days').days);
}

export function localHour(ms: number, tz: string): number {
  return DateTime.fromMillis(ms, { zone: tz }).hour;
}
