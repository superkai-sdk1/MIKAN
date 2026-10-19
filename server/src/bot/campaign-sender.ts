import { and, asc, eq, lte } from 'drizzle-orm';
import type { AppContext } from '../context.js';
import { campaignRecipients, campaigns, clients } from '../db/schema.js';
import {
  campaignStats,
  finishIfDone,
  parseButton,
  startCampaign,
  type CampaignRow,
  type CampaignStats,
  type RecipientRow,
} from '../domain/campaigns.js';
import { studioTimezone } from '../domain/settings.js';
import { errorMessage } from '../lib/errors.js';
import { Pacer, realClock, type Clock } from '../lib/pacer.js';
import type { ClientRow } from '../lib/serialize.js';
import { truncate } from '../lib/text.js';
import { BotSendError, BotUnavailableError, type InlineKeyboard } from './gateway.js';
import { newsKeyboard, personalize, sendNews, storeNews } from './marketing.js';
import { notifyStaff } from './staff.js';

/**
 * Delivers campaigns in the background (docs/API.md «Campaigns»): starts scheduled ones when their time comes, sends
 * the pending recipients at ≤ 20 messages a second, retries failures, and tells the staff chat when a campaign ends.
 * Every recipient's outcome is stored before the next one, so a restart picks up where it stopped.
 */

export const CAMPAIGN_TICK_MS = 5_000;
export const CAMPAIGN_RATE_PER_SECOND = 20;
/** The first try and up to 3 retries (each in a later tick). */
export const CAMPAIGN_MAX_ATTEMPTS = 4;
/** At most this many messages per tick (10 s at the full rate); the rest go in the next ticks. */
const BATCH = 200;
const BLOCKED_ERROR = 'Клиент заблокировал бота или чат недоступен';

export interface CampaignRunStats {
  started: number;
  sent: number;
  failed: number;
  blocked: number;
  retried: number;
  skipped: number;
  finished: number;
}

export interface CampaignRunOptions {
  clock?: Clock;
  /** Messages this run may send at most. */
  maxMessages?: number;
}

/** Why a fixed recipient no longer gets the message, or null. */
function skipReason(client: ClientRow | undefined): string | null {
  if (!client) return 'Клиент удалён';
  if (client.telegramChatId == null) return 'Клиент отвязал Telegram';
  if (!client.botEnabled) return 'Клиент отключил сообщения бота';
  if (client.marketingOptOut) return 'Клиент отказался от новостей';
  if (client.archived) return 'Карточка клиента в архиве';
  return null;
}

function mark(ctx: AppContext, id: number, patch: Partial<RecipientRow>): void {
  ctx.db.update(campaignRecipients).set(patch).where(eq(campaignRecipients.id, id)).run();
}

/** «📣 Рассылка «Осень» завершена» with what came of it. */
export function campaignSummary(title: string, stats: CampaignStats): string {
  if (stats.recipients === 0) return `📣 Рассылка «${title}»: под её условия не подошёл ни один клиент — ничего не отправлено`;
  const skipped = stats.recipients - stats.sent - stats.failed - stats.blocked - stats.pending;
  return [
    `📣 Рассылка «${title}» завершена`,
    `✅ Доставлено: ${stats.sent} из ${stats.recipients}`,
    ...(stats.blocked ? [`🚫 Заблокировали бота: ${stats.blocked}`] : []),
    ...(stats.failed ? [`⚠️ Не доставлено: ${stats.failed}`] : []),
    ...(skipped > 0 ? [`➖ Пропущено (отписались или отвязали Telegram): ${skipped}`] : []),
  ].join('\n');
}

async function announceFinished(ctx: AppContext, row: CampaignRow): Promise<void> {
  await notifyStaff(ctx, campaignSummary(row.title, campaignStats(ctx.db, [row.id]).get(row.id)!));
}

/** Scheduled campaigns whose time has come start now (recipients fixed as of now). */
async function startDue(ctx: AppContext, now: number, stats: CampaignRunStats): Promise<void> {
  const due = ctx.db
    .select()
    .from(campaigns)
    .where(and(eq(campaigns.status, 'scheduled'), lte(campaigns.scheduledAt, now)))
    .orderBy(asc(campaigns.scheduledAt), asc(campaigns.id))
    .all();
  const tz = studioTimezone(ctx.db);
  for (const campaign of due) {
    try {
      const { row } = startCampaign(ctx.db, campaign.id, now, tz, { refuseEmpty: false });
      stats.started += 1;
      if (row.status === 'sent') {
        stats.finished += 1;
        await announceFinished(ctx, row);
      }
    } catch (err) {
      ctx.log.error({ campaignId: campaign.id, err: errorMessage(err) }, 'scheduled campaign did not start');
    }
  }
}

const isSending = (ctx: AppContext, id: number) =>
  ctx.db.select({ status: campaigns.status }).from(campaigns).where(eq(campaigns.id, id)).get()?.status === 'sending';

const recipientRow = (ctx: AppContext, id: number) => ctx.db.select().from(campaignRecipients).where(eq(campaignRecipients.id, id)).get();

interface DeliveryOutcome {
  /** Messages handed to Telegram (successful or not). */
  attempted: number;
  /** The bot went offline: stop for now, nothing was counted against the recipient. */
  offline: boolean;
}

/** Sends one message; the recipient's outcome is stored at once. */
async function deliverOne(
  ctx: AppContext,
  campaign: CampaignRow,
  keyboard: InlineKeyboard,
  recipient: RecipientRow,
  client: ClientRow,
  stats: CampaignRunStats,
  now: () => number,
): Promise<'done' | 'offline'> {
  const chatId = client.telegramChatId!;
  const attempts = recipient.attempts + 1;
  try {
    const stored = await sendNews(ctx, chatId, { text: personalize(campaign.text, client.name), imageUrl: campaign.imageUrl, keyboard });
    mark(ctx, recipient.id, { status: 'sent', attempts, error: null, sentAt: now(), chatId });
    storeNews(ctx.db, chatId, client.id, stored);
    stats.sent += 1;
  } catch (err) {
    if (err instanceof BotUnavailableError) return 'offline';
    if (err instanceof BotSendError && err.blocked) {
      mark(ctx, recipient.id, { status: 'blocked', attempts, error: BLOCKED_ERROR, chatId });
      stats.blocked += 1;
    } else if (attempts >= CAMPAIGN_MAX_ATTEMPTS) {
      mark(ctx, recipient.id, { status: 'failed', attempts, error: truncate(errorMessage(err), 500), chatId });
      stats.failed += 1;
    } else {
      mark(ctx, recipient.id, { attempts, error: truncate(errorMessage(err), 500) });
      stats.retried += 1;
    }
    ctx.log.warn({ campaignId: campaign.id, clientId: client.id, attempts, err: errorMessage(err) }, 'campaign message not delivered');
  }
  return 'done';
}

/**
 * Sends up to `budget` pending messages of one campaign: fresh recipients first, then retries (a recipient that
 * failed in this run waits for the next one). Stops when the campaign is cancelled meanwhile.
 */
async function deliverCampaign(
  ctx: AppContext,
  campaign: CampaignRow,
  pacer: Pacer,
  budget: number,
  stats: CampaignRunStats,
  clock: Clock,
): Promise<DeliveryOutcome> {
  const keyboard = newsKeyboard(ctx, parseButton(campaign.button));
  const batch = ctx.db
    .select()
    .from(campaignRecipients)
    .where(and(eq(campaignRecipients.campaignId, campaign.id), eq(campaignRecipients.status, 'pending')))
    .orderBy(asc(campaignRecipients.attempts), asc(campaignRecipients.id))
    .limit(budget)
    .all();
  let attempted = 0;
  for (const listed of batch) {
    if (!ctx.gateway.isRunning()) return { attempted, offline: true };
    const client = ctx.db.select().from(clients).where(eq(clients.id, listed.clientId)).get();
    const reason = skipReason(client);
    if (!reason) await pacer.wait();
    // Checked after the wait: a cancel that came meanwhile stops the campaign before its next message.
    if (!isSending(ctx, campaign.id)) break;
    const recipient = recipientRow(ctx, listed.id);
    if (recipient?.status !== 'pending') continue;
    if (reason || !client) {
      mark(ctx, recipient.id, { status: 'skipped', error: reason });
      stats.skipped += 1;
      continue;
    }
    attempted += 1;
    if ((await deliverOne(ctx, campaign, keyboard, recipient, client, stats, () => clock.now())) === 'offline') {
      return { attempted, offline: true };
    }
  }
  return { attempted, offline: false };
}

/** One tick of the background sender (every CAMPAIGN_TICK_MS). Does nothing while the bot is offline. */
export async function runCampaigns(ctx: AppContext, options: CampaignRunOptions = {}): Promise<CampaignRunStats> {
  const clock = options.clock ?? realClock;
  const stats: CampaignRunStats = { started: 0, sent: 0, failed: 0, blocked: 0, retried: 0, skipped: 0, finished: 0 };
  if (!ctx.gateway.isRunning()) return stats;
  await startDue(ctx, clock.now(), stats);
  const pacer = new Pacer(clock, CAMPAIGN_RATE_PER_SECOND);
  let budget = options.maxMessages ?? BATCH;
  const sending = ctx.db
    .select()
    .from(campaigns)
    .where(eq(campaigns.status, 'sending'))
    .orderBy(asc(campaigns.startedAt), asc(campaigns.id))
    .all();
  for (const campaign of sending) {
    if (budget <= 0) break;
    const outcome = await deliverCampaign(ctx, campaign, pacer, budget, stats, clock);
    budget -= outcome.attempted;
    if (outcome.offline) break;
    const finished = finishIfDone(ctx.db, campaign.id, clock.now());
    if (finished) {
      stats.finished += 1;
      await announceFinished(ctx, finished);
    }
  }
  return stats;
}
