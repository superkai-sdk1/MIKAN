import { createHash } from 'node:crypto';
import { and, eq, lt } from 'drizzle-orm';
import type { FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Db, DbOrTx } from '../db/client.js';
import { idempotencyKeys } from '../db/schema.js';
import { badRequest, conflict } from './errors.js';

/** How long a stored response is replayed for a repeated key. */
export const IDEMPOTENCY_TTL_MS = 24 * 60 * 60 * 1000;
export const IDEMPOTENCY_HEADER = 'idempotency-key';
/** Set on a response that was replayed from storage instead of being executed again. */
export const REPLAYED_HEADER = 'idempotent-replayed';

const keySchema = z.uuid();

/** The validated, lower-cased `Idempotency-Key` header, or null when the request has none. */
export function idempotencyKeyOf(request: FastifyRequest): string | null {
  const raw = request.headers[IDEMPOTENCY_HEADER];
  if (raw === undefined) return null;
  const parsed = keySchema.safeParse(typeof raw === 'string' ? raw.trim() : raw);
  if (!parsed.success) throw badRequest('Некорректный заголовок Idempotency-Key: ожидается UUID');
  return parsed.data.toLowerCase();
}

/** JSON with object keys sorted, so the same body always hashes the same regardless of key order. */
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${canonicalJson(v)}`).join(',')}}`;
  }
  return JSON.stringify(value) ?? 'null';
}

function requestHash(endpoint: string, body: unknown): string {
  return createHash('sha256').update(`${endpoint}\n${canonicalJson(body ?? null)}`).digest('hex');
}

/**
 * Runs a write at most once per `Idempotency-Key` (per employee, kept 24 h).
 *
 * The first request executes `run` and stores its response in the same transaction; a repeat with the same key,
 * endpoint and body gets the stored response (with `Idempotent-Replayed: true`) without executing `run` again.
 * A repeat with a different endpoint or body is `409 conflict`. Errors are not stored: a failed write changed
 * nothing, so retrying it with the same key simply executes it again. Without the header `run` just executes.
 *
 * Everything here is synchronous (better-sqlite3), so concurrent retries of one key cannot interleave.
 */
export function idempotent<T>(db: Db, request: FastifyRequest, reply: FastifyReply, run: (tx: DbOrTx) => T): T {
  const key = idempotencyKeyOf(request);
  if (!key) return run(db);
  const endpoint = `${request.method} ${request.url.split('?')[0]}`;
  const hash = requestHash(endpoint, request.body);
  const employeeId = request.employee.id;

  return db.transaction((tx) => {
    const now = Date.now();
    tx.delete(idempotencyKeys).where(lt(idempotencyKeys.createdAt, now - IDEMPOTENCY_TTL_MS)).run();
    const stored = tx
      .select()
      .from(idempotencyKeys)
      .where(and(eq(idempotencyKeys.employeeId, employeeId), eq(idempotencyKeys.key, key)))
      .get();
    if (stored) {
      if (stored.requestHash !== hash) {
        throw conflict('Повторный запрос отличается от исходного. Обновите экран и попробуйте снова.');
      }
      reply.header(REPLAYED_HEADER, 'true');
      return JSON.parse(stored.responseJson) as T;
    }
    const response = run(tx);
    tx.insert(idempotencyKeys)
      .values({ key, employeeId, endpoint, requestHash: hash, responseJson: JSON.stringify(response), createdAt: now })
      .run();
    return response;
  });
}
