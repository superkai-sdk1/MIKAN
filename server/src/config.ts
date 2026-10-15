import path from 'node:path';
import { z } from 'zod';
import { SERVICE_IMAGE_MODEL } from './lib/service-images.js';

/** Treat empty env strings as "not set". */
const optionalString = z.preprocess(
  (v) => (typeof v === 'string' && v.trim() === '' ? undefined : v),
  z.string().trim().optional(),
);

const booleanFlag = (defaultValue: boolean) =>
  z.preprocess((v) => {
    if (v === undefined || v === '') return defaultValue;
    if (typeof v === 'string') return ['1', 'true', 'yes', 'on'].includes(v.trim().toLowerCase());
    return v;
  }, z.boolean());

const intWithDefault = (defaultValue: number, min: number, max: number) =>
  z.preprocess(
    (v) => (v === undefined || v === '' ? defaultValue : Number(v)),
    z.number().int().min(min).max(max),
  );

const envSchema = z.object({
  PORT: intWithDefault(3000, 1, 65535),
  HOST: z.string().default('0.0.0.0'),
  DATA_DIR: z.string().default('./data'),
  PUBLIC_URL: optionalString,
  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  ADMIN_LOGIN: z.string().trim().min(2).default('admin'),
  ADMIN_PASSWORD: z.string().min(6, 'ADMIN_PASSWORD must be at least 6 characters'),
  ADMIN_NAME: z.string().trim().min(1).default('Администратор'),
  TELEGRAM_BOT_TOKEN: optionalString,
  TELEGRAM_API_ROOT: z.preprocess(
    (v) => (typeof v === 'string' && v.trim() !== '' ? v.trim().replace(/\/+$/, '') : undefined),
    z.url().default('https://api.telegram.org'),
  ),
  BOT_ENABLED: booleanFlag(false),
  AI_BASE_URL: optionalString,
  AI_API_KEY: optionalString,
  AI_AUTH: z.preprocess(
    (v) => (typeof v === 'string' && v.trim() !== '' ? v.trim().toLowerCase() : undefined),
    z.enum(['bearer', 'x-api-key']).optional(),
  ),
  AI_MODEL: z.string().trim().min(1).default('claude-opus-5-5'),
  AI_IMAGE_MODEL: z.preprocess(
    (v) => (typeof v === 'string' && v.trim() !== '' ? v.trim() : undefined),
    z.string().default(SERVICE_IMAGE_MODEL),
  ),
  AI_HTTPS_PROXY: optionalString,
  AI_MAX_TOKENS: intWithDefault(4096, 256, 64_000),
  AI_DAILY_LIMIT: intWithDefault(500, 0, 1_000_000),
  AI_CHAT_HOURLY_LIMIT: intWithDefault(20, 0, 10_000),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
});

export interface Config {
  port: number;
  host: string;
  dataDir: string;
  publicUrl: string | null;
  jwtSecret: string;
  admin: { login: string; password: string; name: string };
  telegram: { token: string | null; enabled: boolean; apiRoot: string };
  ai: {
    baseUrl: string | null;
    apiKey: string | null;
    auth: 'bearer' | 'x-api-key';
    model: string;
    /** Polza Media API model for service cover pictures. */
    imageModel: string;
    maxTokens: number;
    httpsProxy: string | null;
    dailyLimit: number;
    chatHourlyLimit: number;
  };
  logLevel: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = envSchema.safeParse(env);
  if (!parsed.success) {
    const details = parsed.error.issues
      .map((i) => `${i.path.join('.') || '(env)'}: ${i.message}`)
      .join('; ');
    throw new Error(`Invalid configuration: ${details}`);
  }
  const e = parsed.data;
  const baseUrl = e.AI_BASE_URL ?? null;
  return {
    port: e.PORT,
    host: e.HOST,
    dataDir: path.resolve(e.DATA_DIR),
    publicUrl: e.PUBLIC_URL ?? null,
    jwtSecret: e.JWT_SECRET,
    admin: { login: e.ADMIN_LOGIN, password: e.ADMIN_PASSWORD, name: e.ADMIN_NAME },
    telegram: { token: e.TELEGRAM_BOT_TOKEN ?? null, enabled: e.BOT_ENABLED, apiRoot: e.TELEGRAM_API_ROOT },
    ai: {
      baseUrl,
      apiKey: e.AI_API_KEY ?? null,
      // A custom gateway (e.g. Polza) usually expects a Bearer token; Anthropic direct uses x-api-key.
      auth: e.AI_AUTH ?? (baseUrl ? 'bearer' : 'x-api-key'),
      model: e.AI_MODEL,
      imageModel: e.AI_IMAGE_MODEL,
      maxTokens: e.AI_MAX_TOKENS,
      httpsProxy: e.AI_HTTPS_PROXY ?? null,
      dailyLimit: e.AI_DAILY_LIMIT,
      chatHourlyLimit: e.AI_CHAT_HOURLY_LIMIT,
    },
    logLevel: e.LOG_LEVEL,
  };
}
