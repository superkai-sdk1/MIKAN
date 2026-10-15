import fs from 'node:fs';
import path from 'node:path';
import { pino } from 'pino';
import { APP_VERSION, buildApp } from './app.js';
import { createAiClient } from './bot/ai.js';
import { BotController } from './bot/index.js';
import { processDueMessages, SENDER_INTERVAL_MS } from './bot/sender.js';
import { loadConfig } from './config.js';
import type { AppContext } from './context.js';
import { openDatabase } from './db/client.js';
import { seedDatabase } from './db/seed.js';
import { runBackupIfDue } from './domain/backup.js';
import { studioTimezone } from './domain/settings.js';
import { errorMessage } from './lib/errors.js';

const BACKUP_CHECK_MS = 10 * 60_000;

async function main(): Promise<void> {
  const config = loadConfig();
  const log = pino({
    level: config.logLevel,
    redact: { paths: ['req.headers.authorization', 'password', '*.password', 'token', '*.token'], censor: '[redacted]' },
  });
  fs.mkdirSync(path.join(config.dataDir, 'backups'), { recursive: true });
  const { db, sqlite } = openDatabase(path.join(config.dataDir, 'mikan.db'));
  seedDatabase(db, config);

  const ctx = {
    db,
    sqlite,
    config,
    log,
    ai: createAiClient(config.ai),
    onBotSettingsChanged: () => controller.refresh(),
  } as Omit<AppContext, 'gateway'> as AppContext;
  const controller = new BotController(ctx);
  ctx.gateway = controller;

  const app = await buildApp(ctx, { loggerInstance: log });
  await app.listen({ port: config.port, host: config.host });
  log.info(
    {
      version: APP_VERSION,
      dataDir: config.dataDir,
      ai: ctx.ai ? { model: config.ai.model, gateway: config.ai.baseUrl ?? 'anthropic' } : 'disabled',
      telegram: config.telegram.enabled ? config.telegram.apiRoot : 'disabled',
    },
    'MIKAN server started',
  );

  controller.refresh();

  let sending = false;
  const senderTimer = setInterval(() => {
    if (sending) return;
    sending = true;
    processDueMessages(ctx)
      .catch((err) => log.error({ err: errorMessage(err) }, 'scheduled sender failed'))
      .finally(() => {
        sending = false;
      });
  }, SENDER_INTERVAL_MS);

  const backupDir = path.join(config.dataDir, 'backups');
  const backupTick = () =>
    runBackupIfDue(sqlite, backupDir, studioTimezone(db))
      .then((file) => file && log.info({ file }, 'database backup created'))
      .catch((err) => log.error({ err: errorMessage(err) }, 'database backup failed'));
  const backupTimer = setInterval(backupTick, BACKUP_CHECK_MS);
  void backupTick();

  let shuttingDown = false;
  const shutdown = async (signal: string) => {
    if (shuttingDown) return;
    shuttingDown = true;
    log.info({ signal }, 'shutting down');
    clearInterval(senderTimer);
    clearInterval(backupTimer);
    const force = setTimeout(() => process.exit(1), 15_000);
    force.unref();
    try {
      await controller.stop();
      await app.close();
      sqlite.close();
    } catch (err) {
      log.error({ err: errorMessage(err) }, 'error during shutdown');
    }
    process.exit(0);
  };
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('unhandledRejection', (reason) => log.error({ err: errorMessage(reason) }, 'unhandled rejection'));
}

main().catch((err: unknown) => {
  process.stderr.write(`Fatal: ${errorMessage(err)}\n`);
  process.exit(1);
});
