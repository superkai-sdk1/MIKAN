import { DateTime } from 'luxon';
import type { AppContext } from '../context.js';
import { bonusOperations } from '../db/schema.js';
import { studioTimezone } from './settings.js';

/**
 * Gift bonuses of the birthday greeting and the win-back message (docs/API.md «Birthday and win-back»).
 *
 * TEMPORARY — swap at merge: the loyalty bonus module (built on another branch) owns the bonus ledger. Until it lands,
 * `grantGiftBonuses` writes the `gift` row directly, exactly per the contract («Loyalty bonuses»: a credit lot,
 * `remaining = amount`, burning at `expires_at`). When merging, replace its body with the bonus module's own gift
 * helper so balances, client notifications and the audit follow that module's rules.
 */

/** The last day the gift is valid (`YYYY-MM-DD`, studio time) and the moment it burns: the end of that day. */
export function giftBonusExpiry(now: number, days: number, tz: string): { lastDay: string; expiresAt: number } {
  const lastDay = DateTime.fromMillis(now, { zone: tz }).startOf('day').plus({ days });
  return { lastDay: lastDay.toISODate() ?? '', expiresAt: lastDay.plus({ days: 1 }).toMillis() };
}

/** Credits `amount` gift bonuses that burn after `days` (see `giftBonusExpiry`). */
export function grantGiftBonuses(ctx: Pick<AppContext, 'db'>, clientId: number, amount: number, days: number, note: string, now = Date.now()): void {
  if (amount <= 0) return;
  const { expiresAt } = giftBonusExpiry(now, days, studioTimezone(ctx.db));
  ctx.db
    .insert(bonusOperations)
    .values({ clientId, type: 'gift', amount, remaining: amount, expiresAt, saleId: null, note, employeeId: null, createdAt: now })
    .run();
}
