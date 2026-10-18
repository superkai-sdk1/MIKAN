import { eq } from 'drizzle-orm';
import type { AppContext } from '../context.js';
import type { DbOrTx } from '../db/client.js';
import { employees } from '../db/schema.js';
import { chatEmployee, findChat, setChatEmployee, storeMessage, upsertChat } from '../domain/bot-chats.js';
import { createClient, findClientByChat, findClientByLinkToken, findClientByPhone, linkTelegram } from '../domain/clients.js';
import { getBotSettings, getStudioSettings } from '../domain/settings.js';
import { isPlausiblePhone, normalizePhone } from '../lib/phone.js';
import { clientFullName, type EmployeeRow } from '../lib/serialize.js';
import type { IncomingFrom } from './pipeline.js';
import { bindStaffChat, notifyStaff } from './staff.js';

export interface OnboardingReply {
  text: string;
  /** Whether the chat is linked to a client (controls the "share phone" button). */
  linked: boolean;
  /** The chat belongs to a recognised employee: the staff keyboard is shown. */
  staff?: boolean;
}

/** An active employee whose phone (normalized) is `phone`. */
export function findActiveEmployeeByPhone(db: DbOrTx, phone: string): EmployeeRow | null {
  return (
    db
      .select()
      .from(employees)
      .where(eq(employees.active, true))
      .all()
      .find((e) => e.phone != null && normalizePhone(e.phone) === phone) ?? null
  );
}

export const staffGreeting = (studioName: string, employee: EmployeeRow): string =>
  `Здравствуйте, ${employee.name}! Узнал вас — вы сотрудник ${studioName} ✅\n` +
  'Здесь я помогаю команде: записи (ваши и коллег), карточки клиентов, выручка и аналитика, остатки на складе. ' +
  'Спросите, например: «Что у нас сегодня?», «Выручка за неделю» или «Сколько осталось лабретов 8 мм?».';

export interface SharedContact {
  userId: number | undefined;
  phone: string;
  firstName: string;
  lastName: string | undefined;
}

/** `/start` (optionally with a `c<token>` deep-link payload from POST /clients/:id/telegram-link). */
export function handleStart(ctx: AppContext, from: IncomingFrom, payload: string): OnboardingReply {
  const { db } = ctx;
  const greeting = getBotSettings(db).greeting;
  upsertChat(db, from.chatId, { telegramName: from.telegramName, username: from.username });
  let text = greeting;
  const token = payload.trim();
  if (token.startsWith('c') && token.length > 1) {
    const client = findClientByLinkToken(db, token.slice(1));
    if (client) {
      linkTelegram(db, client.id, from.chatId, from.username);
      text =
        `${client.name}, ваш Telegram подключён к ${getStudioSettings(db).name} ✅\n` +
        'Сюда будут приходить напоминания о записях и рекомендации по уходу после процедур. ' +
        'Если появятся вопросы — просто напишите мне.';
    } else {
      text = `Ссылка для подключения устарела или уже использована — попросите администратора прислать новую.\n\n${greeting}`;
    }
  }
  const employee = chatEmployee(db, findChat(db, from.chatId));
  if (employee && !(token.startsWith('c') && token.length > 1)) text = staffGreeting(getStudioSettings(db).name, employee);
  storeMessage(db, from.chatId, 'system', text);
  return { text, linked: findClientByChat(db, from.chatId) !== null, ...(employee ? { staff: true } : {}) };
}

/**
 * A contact shared via the keyboard button. Only the sender's own contact counts (a forwarded card has another
 * `user_id`). The phone of an active employee turns the chat into a staff chat; any other phone links the chat to the
 * client with that phone, or creates one.
 */
export async function handleContact(
  ctx: AppContext,
  from: IncomingFrom & { userId: number },
  contact: SharedContact,
): Promise<OnboardingReply> {
  const { db } = ctx;
  upsertChat(db, from.chatId, { telegramName: from.telegramName, username: from.username });
  const linkedNow = () => findClientByChat(db, from.chatId) !== null;
  if (contact.userId !== from.userId) {
    return { text: 'Пожалуйста, поделитесь своим номером с помощью кнопки «📱 Поделиться номером» ниже.', linked: linkedNow() };
  }
  const phone = normalizePhone(contact.phone);
  if (!phone || !isPlausiblePhone(phone)) {
    return { text: 'Не получилось распознать номер. Напишите его, пожалуйста, сообщением.', linked: linkedNow() };
  }
  storeMessage(db, from.chatId, 'user', `[Контакт] ${phone}`);
  const employee = findActiveEmployeeByPhone(db, phone);
  if (employee) {
    const wasStaff = findChat(db, from.chatId)?.employeeId === employee.id;
    setChatEmployee(db, from.chatId, employee.id);
    const text = staffGreeting(getStudioSettings(db).name, employee);
    storeMessage(db, from.chatId, 'system', text);
    if (!wasStaff) {
      await notifyStaff(ctx, `🔑 ${employee.name} подключил(а) Telegram к боту как сотрудник${from.username ? ` (@${from.username})` : ''}`);
    }
    return { text, linked: linkedNow(), staff: true };
  }
  // Another phone: the chat is a client's now (an employee who shares a client's number loses staff mode).
  if (findChat(db, from.chatId)?.employeeId != null) setChatEmployee(db, from.chatId, null);
  const existing = findClientByPhone(db, phone);
  let text: string;
  if (existing) {
    linkTelegram(db, existing.id, from.chatId, from.username);
    text = `Спасибо, ${existing.name}! Номер подтверждён ✅ Теперь сюда будут приходить напоминания о записях и рекомендации по уходу.`;
  } else {
    const firstName = contact.firstName.trim();
    const name = firstName || from.telegramName || 'Клиент из Telegram';
    const lastName = (firstName && contact.lastName?.trim()) || null;
    const created = createClient(db, { name, lastName, phone, source: 'telegram' }, { telegramUsername: from.username });
    linkTelegram(db, created.id, from.chatId, from.username);
    await notifyStaff(ctx, `👤 Новый клиент через бота: ${clientFullName(created)}, ${phone}${from.username ? ` (@${from.username})` : ''}`);
    text = `Спасибо, ${name}! Номер сохранён ✅ Чем могу помочь?`;
  }
  storeMessage(db, from.chatId, 'system', text);
  return { text, linked: true };
}

export function handleStaffCommand(ctx: AppContext, chatId: number, code: string): string {
  const result = bindStaffChat(ctx.db, chatId, code);
  if (result === 'locked') {
    return '❌ Слишком много неверных попыток — код аннулирован. Получите новый код в приложении (Настройки → Бот).';
  }
  if (result === 'bound') {
    return (
      `✅ Этот чат подключён для уведомлений ${getStudioSettings(ctx.db).name}: новые заявки на запись, ` +
      'новые клиенты, вопросы, которые бот передал администратору.'
    );
  }
  return '❌ Код неверный или устарел. Получите новый код в приложении (Настройки → Бот) и отправьте: /staff <код>';
}
