/**
 * The only surface through which non-bot code talks to Telegram.
 * Routes and workers depend on this interface, never on grammY directly.
 */
export type PhotoSource = { kind: 'file'; path: string } | { kind: 'url'; url: string };

/** One inline button: `data` is the callback payload (≤ 64 bytes, see TELEGRAM_MAX_CALLBACK_DATA). */
export interface InlineButton {
  text: string;
  data: string;
}

/** Rows of inline buttons under a message. */
export type InlineKeyboard = InlineButton[][];

export interface SendOptions {
  /** Inline buttons under the message (under the last chunk of a long text). */
  keyboard?: InlineKeyboard;
}

export interface SentMessage {
  /** Telegram message id (the last chunk of a long text). */
  messageId: number;
}

export interface BotGateway {
  /** True while long polling is active and messages can be delivered. */
  isRunning(): boolean;
  /** Bot username (without @) once known, else null. */
  username(): string | null;
  sendText(chatId: number, text: string, options?: SendOptions): Promise<SentMessage>;
  sendPhoto(chatId: number, photo: PhotoSource, caption: string, options?: SendOptions): Promise<SentMessage>;
  /** Replaces the photo, caption and buttons of a photo message (carousel paging). */
  editPhoto(chatId: number, messageId: number, photo: PhotoSource, caption: string, keyboard?: InlineKeyboard): Promise<void>;
  /** Replaces the text and buttons of a text message. */
  editText(chatId: number, messageId: number, text: string, keyboard?: InlineKeyboard): Promise<void>;
  /** Replaces the buttons of a message; `null` removes them. */
  editKeyboard(chatId: number, messageId: number, keyboard: InlineKeyboard | null): Promise<void>;
  deleteMessage(chatId: number, messageId: number): Promise<void>;
  sendTyping(chatId: number): Promise<void>;
}

export class BotUnavailableError extends Error {
  constructor(message = 'Telegram-бот не запущен') {
    super(message);
    this.name = 'BotUnavailableError';
  }
}

/** Telegram delivery failure. `blocked` = the user blocked the bot / chat is unreachable (HTTP 403). */
export class BotSendError extends Error {
  readonly blocked: boolean;

  constructor(message: string, blocked: boolean) {
    super(message);
    this.name = 'BotSendError';
    this.blocked = blocked;
  }
}

/** Gateway used when the bot is disabled: reports not running, refuses to send. */
export class OfflineGateway implements BotGateway {
  private readonly cachedUsername: () => string | null;

  constructor(cachedUsername: () => string | null = () => null) {
    this.cachedUsername = cachedUsername;
  }

  isRunning(): boolean {
    return false;
  }

  username(): string | null {
    return this.cachedUsername();
  }

  async sendText(): Promise<SentMessage> {
    throw new BotUnavailableError();
  }

  async sendPhoto(): Promise<SentMessage> {
    throw new BotUnavailableError();
  }

  async editPhoto(): Promise<void> {
    throw new BotUnavailableError();
  }

  async editText(): Promise<void> {
    throw new BotUnavailableError();
  }

  async editKeyboard(): Promise<void> {
    throw new BotUnavailableError();
  }

  async deleteMessage(): Promise<void> {
    throw new BotUnavailableError();
  }

  async sendTyping(): Promise<void> {
    /* nothing to do */
  }
}
