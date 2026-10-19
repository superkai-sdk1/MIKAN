// Transparent reverse proxy to the Telegram Bot API for servers where api.telegram.org is blocked.
// Handles both API calls (/bot<id>:<token>/<method>) and file downloads (/file/bot<id>:<token>/<path>).
// Only bots listed in ALLOWED_BOT_IDS are forwarded, so the worker can't be used as an open proxy.
// The cron trigger additionally checks the MIKAN server from outside (see uptime.js).

import { runUptimeCheck } from "./uptime.js";

const TELEGRAM_ORIGIN = "https://api.telegram.org";
const BOT_PATH = /^\/(?:file\/)?bot(\d+):[A-Za-z0-9_-]+\//;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const match = url.pathname.match(BOT_PATH);
    const allowedIds = (env.ALLOWED_BOT_IDS ?? "")
      .split(",")
      .map((id) => id.trim())
      .filter(Boolean);

    if (!match || !allowedIds.includes(match[1])) {
      return new Response("Not found", { status: 404 });
    }

    const target = new URL(url.pathname + url.search, TELEGRAM_ORIGIN);
    return fetch(new Request(target, request));
  },

  async scheduled(controller, env) {
    await runUptimeCheck(env, controller.scheduledTime);
  },
};
