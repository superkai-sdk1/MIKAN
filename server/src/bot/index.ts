import { Bot, GrammyError, InputFile } from 'grammy';
import type { InlineKeyboardButton, InlineKeyboardMarkup, Message, ReplyKeyboardMarkup } from 'grammy/types';
import type { AppContext } from '../context.js';
import { BOOKING_MENU_TEXT, bookingWebAppUrl } from '../domain/online-booking-links.js';
import { getBotSettings, getCachedBotUsername, setCachedBotUsername } from '../domain/settings.js';
import { errorMessage } from '../lib/errors.js';
import { toPlainText, toTelegramHtml } from '../lib/telegram-format.js';
import { splitMessage, TELEGRAM_MAX_CAPTION, TELEGRAM_MAX_MESSAGE, truncate } from '../lib/text.js';
import {
  BotSendError,
  BotUnavailableError,
  type BotGateway,
  type InlineButton,
  type InlineKeyboard,
  type PhotoSource,
  type SendOptions,
  type SentMessage,
} from './gateway.js';
import { registerHandlers } from './handlers.js';
import { toGrammyKeyboard } from './keyboards.js';
import { BotPipeline } from './pipeline.js';

const MIN_BACKOFF_MS = 5_000;
const MAX_BACKOFF_MS = 5 * 60_000;
const WARN_THROTTLE_MS = 60_000;
const API_TIMEOUT_SECONDS = 75; // > long-polling timeout (30 s)
/** Uploaded pictures remembered by Telegram file_id, so carousel paging does not upload them again. */
const MAX_CACHED_FILE_IDS = 500;

function inlineButton(b: InlineButton): InlineKeyboardButton {
  if (b.url !== undefined) return { text: b.text, url: b.url };
  if (b.webApp !== undefined) return { text: b.text, web_app: { url: b.webApp } };
  return { text: b.text, callback_data: b.data };
}

function markup(keyboard: InlineKeyboard | null | undefined): InlineKeyboardMarkup | undefined {
  if (keyboard === undefined) return undefined;
  return { inline_keyboard: (keyboard ?? []).map((row) => row.map(inlineButton)) };
}

/** Inline buttons win over a keyboard under the input field (a message carries one `reply_markup`). */
function sendMarkup(options: SendOptions): { reply_markup?: InlineKeyboardMarkup | ReplyKeyboardMarkup } {
  if (options.keyboard) return { reply_markup: markup(options.keyboard) };
  if (options.replyKeyboard) return { reply_markup: toGrammyKeyboard(options.replyKeyboard) };
  return {};
}

/** Editing a message to exactly what it already shows is a harmless no-op for us. */
const notModified = (err: unknown): boolean =>
  err instanceof GrammyError && err.error_code === 400 && /message is not modified/i.test(err.description);

/** Telegram rejected the HTML made from the message's Markdown. */
const badMarkup = (err: unknown): boolean =>
  err instanceof GrammyError && err.error_code === 400 && /can't parse entities|unsupported start tag|can't find end/i.test(err.description);

/**
 * Sends `text` with its light Markdown rendered as Telegram HTML; when Telegram rejects the markup, sends it again
 * plain, markers stripped (see lib/telegram-format.ts).
 */
async function withMarkup<T>(text: string, send: (formatted: { text: string; parse_mode?: 'HTML' }) => Promise<T>): Promise<T> {
  try {
    return await send({ text: toTelegramHtml(text), parse_mode: 'HTML' });
  } catch (err) {
    if (!badMarkup(err)) throw err;
    return send({ text: toPlainText(text) });
  }
}

function toSendError(err: unknown): BotSendError {
  if (err instanceof GrammyError) {
    const unreachable = err.error_code === 403 || (err.error_code === 400 && /chat not found|user not found/i.test(err.description));
    return new BotSendError(`Telegram: ${err.description}`, unreachable);
  }
  return new BotSendError(`Telegram недоступен: ${errorMessage(err)}`, false);
}

/**
 * Owns the grammY bot: long polling with restart/backoff on fatal errors, and the BotGateway used
 * by routes and workers. The HTTP API never depends on Telegram being reachable.
 */
export interface BotControllerOptions {
  /** Test seam: builds the grammY bot (handlers included). Defaults to a real Bot via TELEGRAM_API_ROOT. */
  botFactory?: (token: string) => Bot;
  debounceMs?: number;
}

export class BotController implements BotGateway {
  readonly pipeline: BotPipeline;
  private bot: Bot | null = null;
  private polling = false;
  private active = false;
  /** Bumped on every start/stop; a loop only touches shared state while its generation is current. */
  private generation = 0;
  private loopPromise: Promise<void> | null = null;
  private abort: AbortController | null = null;
  private wakeUp: (() => void) | null = null;
  private lastWarnAt = 0;
  private apiFailing = false;
  private readonly botFactory: (token: string) => Bot;
  /** Local path / URL of a sent picture → its Telegram file_id. */
  private readonly fileIds = new Map<string, string>();

  constructor(
    private readonly ctx: AppContext,
    options: BotControllerOptions = {},
  ) {
    this.pipeline = new BotPipeline(ctx, options.debounceMs);
    this.botFactory = options.botFactory ?? ((token) => this.createBot(token));
  }

  isRunning(): boolean {
    return this.polling && this.bot !== null;
  }

  username(): string | null {
    return this.bot?.isInited() ? this.bot.botInfo.username : getCachedBotUsername(this.ctx.db);
  }

  private shouldRun(): boolean {
    const { token, enabled } = this.ctx.config.telegram;
    return enabled && token !== null && getBotSettings(this.ctx.db).enabled;
  }

  /** Starts or stops polling to match env + settings. Safe to call repeatedly. */
  refresh(): void {
    if (this.shouldRun() && !this.active) {
      if (this.loopPromise) {
        // The previous loop is still unwinding (grammY's stop() finishes one last getUpdates);
        // start again only once it has fully stopped, so two pollers never overlap (409).
        void this.loopPromise.then(() => this.refresh());
        return;
      }
      this.active = true;
      const generation = ++this.generation;
      this.loopPromise = this.loop(generation).finally(() => {
        this.loopPromise = null;
      });
    } else if (!this.shouldRun() && this.active) {
      void this.stop();
    }
  }

  async stop(): Promise<void> {
    this.active = false;
    this.generation += 1;
    this.abort?.abort();
    this.wakeUp?.();
    const bot = this.bot;
    if (bot?.isRunning()) await bot.stop().catch(() => undefined);
    await this.loopPromise;
    // The stopped loop no longer owns `polling` (its generation is stale); clear it unless a new loop started.
    if (!this.active) this.polling = false;
    await this.pipeline.idle();
  }

  private warn(message: string, err: unknown): void {
    const now = Date.now();
    if (now - this.lastWarnAt < WARN_THROTTLE_MS) return;
    this.lastWarnAt = now;
    this.ctx.log.warn({ err: errorMessage(err) }, message);
  }

  private createBot(token: string): Bot {
    const bot = new Bot(token, { client: { apiRoot: this.ctx.config.telegram.apiRoot, timeoutSeconds: API_TIMEOUT_SECONDS } });
    // Log (throttled) every failing API call, and when the connection recovers.
    bot.api.config.use(async (prev, method, payload, signal) => {
      try {
        const result = await prev(method, payload, signal);
        if (this.apiFailing) {
          this.apiFailing = false;
          this.ctx.log.info('Telegram API reachable again');
        }
        return result;
      } catch (err) {
        if (!(err instanceof GrammyError) && !signal?.aborted) {
          this.apiFailing = true;
          this.warn(`Telegram API call ${method} failed, grammY will retry`, err);
        }
        throw err;
      }
    });
    registerHandlers(bot, { ctx: this.ctx, pipeline: this.pipeline, downloadFile: (id, max) => this.downloadFile(bot, token, id, max) });
    bot.catch((err) => {
      this.ctx.log.error({ err: errorMessage(err.error), updateId: err.ctx.update.update_id }, 'bot handler failed');
    });
    return bot;
  }

  private async loop(generation: number): Promise<void> {
    const token = this.ctx.config.telegram.token!;
    const current = () => this.active && generation === this.generation;
    let backoff = MIN_BACKOFF_MS;
    while (current()) {
      const bot = this.botFactory(token);
      this.bot = bot;
      this.abort = new AbortController();
      try {
        // Retries network errors internally; throws on 401. grammY types its own AbortSignal shim.
        await bot.init(this.abort.signal as unknown as Parameters<Bot['init']>[0]);
        setCachedBotUsername(this.ctx.db, bot.botInfo.username);
        if (!current()) break;
        await bot.start({
          allowed_updates: ['message', 'callback_query'],
          onStart: (info) => {
            if (!current()) return;
            this.polling = true;
            backoff = MIN_BACKOFF_MS;
            this.ctx.log.info({ username: info.username }, 'Telegram bot polling started');
            void this.setBookingMenuButton(bot);
          },
        });
        if (generation === this.generation) this.polling = false;
        if (current()) this.ctx.log.warn('Telegram polling stopped unexpectedly; restarting');
      } catch (err) {
        if (generation === this.generation) this.polling = false;
        if (!current()) break;
        const hint =
          err instanceof GrammyError && err.error_code === 401
            ? ' (invalid TELEGRAM_BOT_TOKEN?)'
            : err instanceof GrammyError && err.error_code === 409
              ? ' (another instance is polling this bot?)'
              : '';
        this.ctx.log.warn({ err: errorMessage(err), retryInMs: backoff }, `Telegram bot failed${hint}`);
      }
      if (!current()) break;
      await new Promise<void>((resolve) => {
        const timer = setTimeout(resolve, backoff);
        this.wakeUp = () => {
          clearTimeout(timer);
          resolve();
        };
      });
      this.wakeUp = null;
      backoff = Math.min(backoff * 2, MAX_BACKOFF_MS);
    }
    if (generation === this.generation) this.polling = false;
  }

  /**
   * The chat menu button opens the booking Mini App («📅 Записаться», docs/API.md «Online booking»); without an
   * `https://` PUBLIC_URL the default menu stays. A failure is only logged.
   */
  private async setBookingMenuButton(bot: Bot): Promise<void> {
    const url = bookingWebAppUrl(this.ctx.config);
    if (!url) return;
    try {
      await bot.api.setChatMenuButton({ menu_button: { type: 'web_app', text: BOOKING_MENU_TEXT, web_app: { url } } });
    } catch (err) {
      this.ctx.log.warn({ err: errorMessage(err) }, 'bot menu button not set');
    }
  }

  private requireBot(): Bot {
    if (!this.bot || !this.polling) throw new BotUnavailableError();
    return this.bot;
  }

  async sendText(chatId: number, text: string, options: SendOptions = {}): Promise<SentMessage> {
    const bot = this.requireBot();
    const chunks = splitMessage(text);
    let messageId = 0;
    for (const [index, chunk] of chunks.entries()) {
      const last = index === chunks.length - 1;
      try {
        const sent = await withMarkup(chunk, (formatted) =>
          bot.api.sendMessage(chatId, formatted.text, {
            ...(formatted.parse_mode ? { parse_mode: formatted.parse_mode } : {}),
            link_preview_options: { is_disabled: true },
            ...(last ? sendMarkup(options) : {}),
          }),
        );
        messageId = sent.message_id;
      } catch (err) {
        throw toSendError(err);
      }
    }
    return { messageId };
  }

  /** A cached file_id for an already uploaded picture, else the file / URL itself. */
  private photoInput(photo: PhotoSource): { key: string; input: InputFile | string } {
    const key = photo.kind === 'file' ? `file:${photo.path}` : `url:${photo.url}`;
    const cached = this.fileIds.get(key);
    if (cached) return { key, input: cached };
    return { key, input: photo.kind === 'file' ? new InputFile(photo.path) : photo.url };
  }

  private rememberFileId(key: string, message: Message | true | undefined): void {
    if (!message || message === true || !('photo' in message) || !message.photo?.length) return;
    if (this.fileIds.size >= MAX_CACHED_FILE_IDS) this.fileIds.delete(this.fileIds.keys().next().value!);
    this.fileIds.set(key, message.photo[message.photo.length - 1]!.file_id);
  }

  async sendPhoto(chatId: number, photo: PhotoSource, caption: string, options: SendOptions = {}): Promise<SentMessage> {
    const bot = this.requireBot();
    const { key, input } = this.photoInput(photo);
    try {
      const sent = await withMarkup(truncate(caption, TELEGRAM_MAX_CAPTION), (formatted) =>
        bot.api.sendPhoto(chatId, input, {
          caption: formatted.text,
          ...(formatted.parse_mode ? { parse_mode: formatted.parse_mode } : {}),
          ...(options.keyboard ? { reply_markup: markup(options.keyboard) } : {}),
        }),
      );
      this.rememberFileId(key, sent);
      return { messageId: sent.message_id };
    } catch (err) {
      throw toSendError(err);
    }
  }

  async editPhoto(chatId: number, messageId: number, photo: PhotoSource, caption: string, keyboard?: InlineKeyboard): Promise<void> {
    const bot = this.requireBot();
    const { key, input } = this.photoInput(photo);
    try {
      const edited = await withMarkup(truncate(caption, TELEGRAM_MAX_CAPTION), (formatted) =>
        bot.api.editMessageMedia(
          chatId,
          messageId,
          { type: 'photo', media: input, caption: formatted.text, ...(formatted.parse_mode ? { parse_mode: formatted.parse_mode } : {}) },
          { reply_markup: markup(keyboard ?? []) },
        ),
      );
      this.rememberFileId(key, edited);
    } catch (err) {
      if (!notModified(err)) throw toSendError(err);
    }
  }

  async editText(chatId: number, messageId: number, text: string, keyboard?: InlineKeyboard): Promise<void> {
    const bot = this.requireBot();
    try {
      await withMarkup(truncate(text, TELEGRAM_MAX_MESSAGE), (formatted) =>
        bot.api.editMessageText(chatId, messageId, formatted.text, {
          ...(formatted.parse_mode ? { parse_mode: formatted.parse_mode } : {}),
          link_preview_options: { is_disabled: true },
          reply_markup: markup(keyboard ?? []),
        }),
      );
    } catch (err) {
      if (!notModified(err)) throw toSendError(err);
    }
  }

  async editKeyboard(chatId: number, messageId: number, keyboard: InlineKeyboard | null): Promise<void> {
    const bot = this.requireBot();
    try {
      await bot.api.editMessageReplyMarkup(chatId, messageId, { reply_markup: markup(keyboard) });
    } catch (err) {
      if (!notModified(err)) throw toSendError(err);
    }
  }

  async deleteMessage(chatId: number, messageId: number): Promise<void> {
    const bot = this.requireBot();
    try {
      await bot.api.deleteMessage(chatId, messageId);
    } catch (err) {
      throw toSendError(err);
    }
  }

  async sendTyping(chatId: number): Promise<void> {
    if (!this.bot || !this.polling) return;
    await this.bot.api.sendChatAction(chatId, 'typing');
  }

  /** Downloads through TELEGRAM_API_ROOT (Cloudflare Worker in prod). The URL contains the token — never log it. */
  private async downloadFile(bot: Bot, token: string, fileId: string, maxBytes: number): Promise<Buffer | null> {
    const file = await bot.api.getFile(fileId);
    if (!file.file_path || (file.file_size ?? 0) > maxBytes) return null;
    const response = await fetch(`${this.ctx.config.telegram.apiRoot}/file/bot${token}/${file.file_path}`, {
      signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) throw new Error(`file download failed with HTTP ${response.status}`);
    const buffer = Buffer.from(await response.arrayBuffer());
    return buffer.length > maxBytes ? null : buffer;
  }
}
