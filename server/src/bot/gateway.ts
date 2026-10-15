/**
 * The only surface through which non-bot code talks to Telegram.
 * Routes and workers depend on this interface, never on grammY directly.
 */
export type PhotoSource = { kind: 'file'; path: string } | { kind: 'url'; url: string };

export interface BotGateway {
  /** True while long polling is active and messages can be delivered. */
  isRunning(): boolean;
  /** Bot username (without @) once known, else null. */
  username(): string | null;
  sendText(chatId: number, text: string): Promise<void>;
  sendPhoto(chatId: number, photo: PhotoSource, caption: string): Promise<void>;
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

  async sendText(): Promise<void> {
    throw new BotUnavailableError();
  }

  async sendPhoto(): Promise<void> {
    throw new BotUnavailableError();
  }

  async sendTyping(): Promise<void> {
    /* nothing to do */
  }
}
