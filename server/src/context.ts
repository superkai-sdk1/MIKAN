import type Anthropic from '@anthropic-ai/sdk';
import type { BotGateway } from './bot/gateway.js';
import type { Config } from './config.js';
import type { Db, Sqlite } from './db/client.js';

export interface Logger {
  debug(obj: unknown, msg?: string): void;
  info(obj: unknown, msg?: string): void;
  warn(obj: unknown, msg?: string): void;
  error(obj: unknown, msg?: string): void;
}

/** Minimal Claude Messages API surface the bot needs (real SDK client in prod, scripted fake in tests). */
export interface AiClient {
  model: string;
  /** Includes adaptive thinking, which counts toward max_tokens. */
  maxTokens: number;
  createMessage(params: Anthropic.MessageCreateParamsNonStreaming): Promise<Anthropic.Message>;
}

export interface AppContext {
  db: Db;
  sqlite: Sqlite;
  config: Config;
  log: Logger;
  gateway: BotGateway;
  /** null when no AI key is configured. */
  ai: AiClient | null;
  /** Invoked after bot settings change (start/stop polling). */
  onBotSettingsChanged: () => void;
}

export const silentLogger: Logger = {
  debug: () => undefined,
  info: () => undefined,
  warn: () => undefined,
  error: () => undefined,
};
