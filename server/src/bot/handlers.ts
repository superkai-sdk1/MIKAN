import { Keyboard, type Bot, type Context } from 'grammy';
import type { AppContext } from '../context.js';
import { errorMessage } from '../lib/errors.js';
import { handleContact, handleStaffCommand, handleStart } from './onboarding.js';
import type { BotPipeline, IncomingFrom } from './pipeline.js';
import type { PendingImage } from './prompt.js';

export const MAX_CLIENT_IMAGE_BYTES = 5 * 1024 * 1024;

export const BUTTONS = {
  services: '💉 Услуги и цены',
  jewelry: '💎 Украшения',
  booking: '📅 Записаться',
  aftercare: '🩹 Уход после процедуры',
  contact: '📱 Поделиться номером',
} as const;

export function mainKeyboard(linked: boolean): Keyboard {
  const keyboard = new Keyboard()
    .text(BUTTONS.services)
    .text(BUTTONS.jewelry)
    .row()
    .text(BUTTONS.booking)
    .text(BUTTONS.aftercare);
  if (!linked) keyboard.row().requestContact(BUTTONS.contact);
  return keyboard.resized().persistent();
}

export interface HandlerDeps {
  ctx: AppContext;
  pipeline: BotPipeline;
  /** Downloads a Telegram file (≤ maxBytes) via the configured API root; null if too big/unavailable. */
  downloadFile(fileId: string, maxBytes: number): Promise<Buffer | null>;
}

function sender(c: Context): IncomingFrom {
  const name = [c.from?.first_name, c.from?.last_name].filter(Boolean).join(' ').trim();
  return { chatId: c.chat!.id, telegramName: name || null, username: c.from?.username ?? null };
}

const IMAGE_TYPES: Record<string, PendingImage['mediaType']> = {
  'image/jpeg': 'image/jpeg',
  'image/png': 'image/png',
  'image/webp': 'image/webp',
};

async function fetchImage(deps: HandlerDeps, fileId: string, mediaType: PendingImage['mediaType']): Promise<PendingImage | undefined> {
  try {
    const buffer = await deps.downloadFile(fileId, MAX_CLIENT_IMAGE_BYTES);
    return buffer ? { data: buffer.toString('base64'), mediaType } : undefined;
  } catch (err) {
    deps.ctx.log.warn({ err: errorMessage(err) }, 'failed to download client photo');
    return undefined;
  }
}

export function registerHandlers(bot: Bot, deps: HandlerDeps): void {
  const { ctx, pipeline } = deps;

  // Works in any chat (group or private): binds the staff notification chat.
  bot.command('staff', async (c) => {
    await c.reply(handleStaffCommand(ctx, c.chat.id, String(c.match ?? '')));
  });

  const pm = bot.chatType('private');

  pm.command('start', async (c) => {
    const reply = handleStart(ctx, sender(c), String(c.match ?? ''));
    await c.reply(reply.text, { reply_markup: mainKeyboard(reply.linked) });
  });

  pm.on('message:contact', async (c) => {
    const contact = c.message.contact;
    const reply = await handleContact(
      ctx,
      { ...sender(c), userId: c.from.id },
      { userId: contact.user_id, phone: contact.phone_number, firstName: contact.first_name, lastName: contact.last_name },
    );
    await c.reply(reply.text, { reply_markup: mainKeyboard(reply.linked) });
  });

  pm.on('message:photo', async (c) => {
    const sizes = [...c.message.photo].reverse();
    const best = sizes.find((s) => (s.file_size ?? 0) <= MAX_CLIENT_IMAGE_BYTES);
    const caption = c.message.caption?.trim();
    // Not awaited: grammY handles updates one by one, so a slow download must not stall other chats.
    // The pipeline awaits the promise when it builds the AI request.
    const image = best ? fetchImage(deps, best.file_id, 'image/jpeg') : undefined;
    pipeline.receive(sender(c), caption ? `[Фото] ${caption}` : '[Фото]', image);
  });

  pm.on('message:document', async (c) => {
    const doc = c.message.document;
    const caption = c.message.caption?.trim();
    const mediaType = doc.mime_type ? IMAGE_TYPES[doc.mime_type] : undefined;
    if (mediaType && (doc.file_size ?? 0) <= MAX_CLIENT_IMAGE_BYTES) {
      const image = fetchImage(deps, doc.file_id, mediaType);
      pipeline.receive(sender(c), caption ? `[Фото] ${caption}` : '[Фото]', image);
      return;
    }
    pipeline.receive(sender(c), `[Файл «${doc.file_name ?? 'без названия'}»]${caption ? ` ${caption}` : ''}`);
  });

  pm.on(['message:voice', 'message:audio'], async (c) => {
    await pipeline.receiveUnsupported(sender(c), '[Голосовое сообщение]');
  });

  pm.on(['message:video', 'message:video_note'], async (c) => {
    await pipeline.receiveUnsupported(sender(c), '[Видео]');
  });

  pm.on('message:sticker', async (c) => {
    pipeline.receive(sender(c), `[Стикер ${c.message.sticker.emoji ?? ''}]`.replace(' ]', ']'));
  });

  pm.on('message:text', async (c) => {
    pipeline.receive(sender(c), c.message.text);
  });
}
