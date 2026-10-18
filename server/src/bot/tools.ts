import type Anthropic from '@anthropic-ai/sdk';
import { and, desc, eq, inArray } from 'drizzle-orm';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { bookingRequests, botMessages, products, services } from '../db/schema.js';
import { findChat, updateChatFlags } from '../domain/bot-chats.js';
import { hasSizeInStock } from '../domain/products.js';
import { normalizePhone, isPlausiblePhone } from '../lib/phone.js';
import type { ProductRow, ServiceRow } from '../lib/serialize.js';
import { truncate } from '../lib/text.js';
import { photoMessageText, servicePhotoSource } from './media.js';
import { HISTORY_LIMIT } from './prompt.js';
import { clientLabel, notifyStaff } from './staff.js';

export const MAX_PRODUCTS_PER_CALL = 5;

export const TOOLS: Anthropic.Tool[] = [
  {
    name: 'create_booking_request',
    description:
      'Создаёт заявку на запись для администратора. Вызывай, когда клиент хочет записаться и ты уже знаешь его имя, ' +
      'телефон, желаемую услугу и удобное время. Время не подтверждается автоматически — администратор свяжется с клиентом.',
    input_schema: {
      type: 'object',
      properties: {
        contactName: { type: 'string', description: 'Имя клиента' },
        phone: { type: 'string', description: 'Телефон клиента для связи' },
        serviceName: { type: 'string', description: 'Желаемая услуга, например «прокол хеликса» или «тату на предплечье»' },
        preferredTime: { type: 'string', description: 'Удобные дата и время словами клиента, например «в субботу после 15:00»' },
        comment: { type: 'string', description: 'Детали: зона, размер, эскиз, выбранное украшение и т. п. Можно пустую строку.' },
      },
      required: ['contactName', 'phone', 'serviceName', 'preferredTime'],
    },
  },
  {
    name: 'handoff_to_staff',
    description:
      'Передаёт диалог живому администратору. Вызывай при признаках осложнений после процедуры (гной, нарастающий отёк, ' +
      'сильная боль, температура, аллергия), при жалобах, просьбе позвать человека, вопросах, на которые нет ответа в данных студии.',
    input_schema: {
      type: 'object',
      properties: { reason: { type: 'string', description: 'Кратко: почему нужен администратор' } },
      required: ['reason'],
    },
  },
  {
    name: 'show_products',
    description:
      'Отправляет клиенту фото украшений из списка «Украшения в наличии» (с названием, материалом, толщиной, ценой и размерами в наличии). ' +
      'Вызывай, когда клиент хочет посмотреть варианты. Фото придут сразу после твоего текстового ответа.',
    input_schema: {
      type: 'object',
      properties: {
        productIds: {
          type: 'array',
          items: { type: 'integer' },
          description: `id украшений из списка (не больше ${MAX_PRODUCTS_PER_CALL})`,
        },
      },
      required: ['productIds'],
    },
  },
  {
    name: 'show_service',
    description:
      'Отправляет клиенту схематичную картинку услуги из раздела «Услуги и цены» с подписью: название, цена, варианты ' +
      'и краткое описание. Вызывай, когда клиент спрашивает о конкретной услуге, выбирает её или консультация идёт об ' +
      'одной услуге. Картинка придёт сразу после твоего текстового ответа, поэтому не повторяй в тексте все цены и ' +
      'варианты. Для каждой услуги — не больше одного раза за диалог. Работает только для услуг с пометкой «есть ' +
      'картинка»: если её нет, просто ответь текстом. Никогда не придумывай и не описывай картинки, которых нет.',
    input_schema: {
      type: 'object',
      properties: { serviceId: { type: 'integer', description: 'id услуги из раздела «Услуги и цены»' } },
      required: ['serviceId'],
    },
  },
];

const bookingInput = z.object({
  contactName: z.string().trim().min(1).max(100),
  phone: z.string().trim().min(3).max(40),
  serviceName: z.string().trim().min(1).max(200),
  preferredTime: z.string().trim().min(1).max(200),
  comment: z.string().trim().max(1000).nullish(),
});
const handoffInput = z.object({ reason: z.string().trim().min(1).max(500) });
const productsInput = z.object({ productIds: z.array(z.number().int().positive()).min(1).max(MAX_PRODUCTS_PER_CALL) });
const serviceInput = z.object({ serviceId: z.number().int().positive() });

export interface ToolResult {
  content: string;
  isError?: boolean;
}
export type ToolHandler = (input: unknown) => Promise<ToolResult>;

export interface ToolScope {
  mode: 'live' | 'test';
  chatId: number | null;
  clientId: number | null;
  telegramName: string | null;
  username: string | null;
  lastUserText: string;
}

/** Collects side effects that happen after the text reply (service pictures, product photos) and test-mode notes. */
export interface ToolSink {
  products: ProductRow[];
  services: ServiceRow[];
  notes: string[];
  /** Live actions that succeeded (used to confirm them if the model ends without text). */
  done: Set<'booking' | 'handoff'>;
}

const invalid = (what: string): ToolResult => ({ content: `Некорректные данные: ${what}. Уточни у клиента и попробуй снова.`, isError: true });

function availableJewelry(ctx: AppContext, ids: number[]): ProductRow[] {
  const rows = ctx.db
    .select()
    .from(products)
    .where(and(inArray(products.id, ids), eq(products.kind, 'jewelry'), eq(products.active, true), hasSizeInStock))
    .all();
  return ids.map((id) => rows.find((r) => r.id === id)).filter((r): r is ProductRow => r !== undefined);
}

function activeService(ctx: AppContext, id: number): ServiceRow | undefined {
  return ctx.db.select().from(services).where(and(eq(services.id, id), eq(services.active, true))).get();
}

/** Whether this service's picture is already in the part of the chat the model sees. */
function serviceShownRecently(ctx: AppContext, chatId: number | null, service: ServiceRow): boolean {
  if (chatId === null) return false;
  const marker = photoMessageText(`${service.name}\n`);
  return ctx.db
    .select({ role: botMessages.role, text: botMessages.text })
    .from(botMessages)
    .where(eq(botMessages.chatId, chatId))
    .orderBy(desc(botMessages.id))
    .limit(HISTORY_LIMIT)
    .all()
    .some((m) => m.role === 'assistant' && m.text.startsWith(marker));
}

export function buildToolHandlers(ctx: AppContext, scope: ToolScope, sink: ToolSink): Record<string, ToolHandler> {
  const who = clientLabel(scope.telegramName, scope.username);
  return {
    create_booking_request: async (raw) => {
      const parsed = bookingInput.safeParse(raw);
      if (!parsed.success) {
        const fields = [...new Set(parsed.error.issues.map((i) => i.path.join('.')))].join(', ');
        return invalid(`проверь поля ${fields} (имя, телефон, услуга и время обязательны)`);
      }
      const input = parsed.data;
      const phone = normalizePhone(input.phone);
      if (!phone || !isPlausiblePhone(phone)) return invalid('телефон выглядит неправильно');
      if (scope.mode === 'test') {
        sink.notes.push(`создана бы заявка: ${input.contactName}, ${phone}, ${input.serviceName}, ${input.preferredTime}`);
        return { content: 'Тестовый режим: заявка не сохранена, но для клиента всё выглядит так, будто она создана.' };
      }
      const now = Date.now();
      const row = ctx.db
        .insert(bookingRequests)
        .values({
          chatId: scope.chatId,
          clientId: scope.clientId,
          contactName: input.contactName,
          phone,
          serviceName: input.serviceName,
          preferredTime: input.preferredTime,
          comment: input.comment || null,
          status: 'new',
          createdAt: now,
          updatedAt: now,
        })
        .returning()
        .get();
      await notifyStaff(
        ctx,
        [
          `📅 Новая заявка на запись №${row.id}`,
          `Имя: ${input.contactName}`,
          `Телефон: ${phone}`,
          `Услуга: ${input.serviceName}`,
          `Когда удобно: ${input.preferredTime}`,
          ...(input.comment ? [`Комментарий: ${input.comment}`] : []),
          `Telegram: ${who}`,
        ].join('\n'),
      );
      sink.done.add('booking');
      return { content: `Заявка №${row.id} создана. Администратор свяжется с клиентом, чтобы подтвердить время.` };
    },

    handoff_to_staff: async (raw) => {
      const parsed = handoffInput.safeParse(raw);
      if (!parsed.success) return invalid('укажи причину');
      if (scope.mode === 'test') {
        sink.notes.push(`диалог передан бы администратору: ${parsed.data.reason}`);
        return { content: 'Тестовый режим: администратор не уведомлён, но для клиента всё выглядит как обычно.' };
      }
      if (scope.chatId !== null && findChat(ctx.db, scope.chatId)) {
        updateChatFlags(ctx.db, scope.chatId, { needsAttention: true });
      }
      await notifyStaff(
        ctx,
        `🙋 Бот передал диалог администратору\nКлиент: ${who}\nПричина: ${parsed.data.reason}\n` +
          `Последнее сообщение: «${truncate(scope.lastUserText, 500)}»\nОтветьте в приложении MIKAN.`,
      );
      sink.done.add('handoff');
      return { content: 'Администратор уведомлён и скоро ответит в этом чате.' };
    },

    show_products: async (raw) => {
      const parsed = productsInput.safeParse(raw);
      if (!parsed.success) return invalid(`нужен список id (от 1 до ${MAX_PRODUCTS_PER_CALL})`);
      const found = availableJewelry(ctx, parsed.data.productIds);
      if (found.length === 0) return { content: 'Этих украшений сейчас нет в наличии. Предложи другие из списка.', isError: true };
      const fresh = found.filter((p) => !sink.products.some((q) => q.id === p.id));
      sink.products.push(...fresh);
      if (scope.mode === 'test') sink.notes.push(`показаны бы фото: ${found.map((p) => p.name).join(', ')}`);
      return { content: `Фото будут отправлены клиенту после твоего ответа: ${found.map((p) => p.name).join(', ')}.` };
    },

    show_service: async (raw) => {
      const parsed = serviceInput.safeParse(raw);
      if (!parsed.success) return invalid('нужен id услуги из раздела «Услуги и цены»');
      const service = activeService(ctx, parsed.data.serviceId);
      if (!service) return { content: 'Такой услуги нет в прайсе. Возьми id из раздела «Услуги и цены».', isError: true };
      if (!servicePhotoSource(ctx.config.dataDir, service)) {
        return { content: `У услуги «${service.name}» нет картинки — просто ответь клиенту текстом.` };
      }
      if (sink.services.some((s) => s.id === service.id) || serviceShownRecently(ctx, scope.chatId, service)) {
        return { content: `Картинка услуги «${service.name}» уже отправлена клиенту в этом диалоге — не отправляй её повторно.` };
      }
      sink.services.push(service);
      if (scope.mode === 'test') sink.notes.push(`показана бы картинка услуги: ${service.name}`);
      return { content: `Картинка услуги «${service.name}» с ценой и вариантами будет отправлена клиенту после твоего ответа.` };
    },
  };
}
