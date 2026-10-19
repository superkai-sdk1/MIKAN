import { and, eq } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { pushDevices } from '../db/schema.js';
import { badRequest } from '../lib/errors.js';
import type { ApnsEnvironment } from './apns.js';

/** The staff iPhones that get pushes: registered after sign-in, removed on sign-out or when Apple rejects them. */

/** APNs tokens are hex of variable length (32 bytes today); stored lowercase. */
const DEVICE_TOKEN = /^(?:[0-9a-f]{2}){16,100}$/;

/** The token in its stored form, or `400` «Некорректный токен устройства». */
export function deviceToken(value: unknown): string {
  const token = typeof value === 'string' ? value.trim().toLowerCase() : '';
  if (!DEVICE_TOKEN.test(token)) throw badRequest('Некорректный токен устройства');
  return token;
}

/** Registers the device for the employee: a token registered by someone else moves to them; `lastSeenAt` is now. */
export function registerDevice(
  db: DbOrTx,
  employeeId: number,
  device: { token: string; environment: ApnsEnvironment },
  now = Date.now(),
): void {
  db.insert(pushDevices)
    .values({ employeeId, token: device.token, environment: device.environment, createdAt: now, lastSeenAt: now })
    .onConflictDoUpdate({
      target: pushDevices.token,
      set: { employeeId, environment: device.environment, lastSeenAt: now },
    })
    .run();
}

/** Sign-out: removes the employee's own device (someone else's token is left alone). */
export function unregisterDevice(db: DbOrTx, employeeId: number, token: string): void {
  db.delete(pushDevices)
    .where(and(eq(pushDevices.token, token), eq(pushDevices.employeeId, employeeId)))
    .run();
}
