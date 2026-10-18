import { and, asc, eq, inArray } from 'drizzle-orm';
import type { AppContext } from '../context.js';
import type { DbOrTx } from '../db/client.js';
import { catalogCategories, products, productServices, services } from '../db/schema.js';
import { storeMessage } from '../domain/bot-chats.js';
import { hasSizeInStock, serviceIdsByProduct, variantsByProduct } from '../domain/products.js';
import { errorMessage } from '../lib/errors.js';
import { formatThickness, threadLabel } from '../lib/jewelry.js';
import type { ProductRow, ServiceRow, VariantRow } from '../lib/serialize.js';
import { formatRub, TELEGRAM_MAX_CAPTION, truncate } from '../lib/text.js';
import {
  encodeCallback,
  type CallbackAction,
  type JewelryList,
  type ServiceCategoryKey,
  type ServiceList,
} from './callback-data.js';
import type { InlineButton, InlineKeyboard, PhotoSource } from './gateway.js';
import { photoSourceFor, serviceCaption, servicePhotoSource } from './media.js';

/**
 * Interactive catalogs in Telegram: menus of categories and carousels (one message paged with ◀︎ / ▶︎) of jewelry in
 * stock and of services. Captions name sizes in stock and prices — never how many pieces are left.
 */

const DESCRIPTION_MAX = 200;
const MENU_COLUMNS = 2;

export const CATALOG_BUTTONS = {
  want: '💍 Хочу это украшение',
  allJewelry: '📂 Все украшения',
  book: '📅 Записаться',
  jewelryForService: '💎 Подходящие украшения',
  allServices: '📂 Все услуги',
  services: '💉 Услуги и цены',
  jewelry: '💎 Украшения',
  back: '◀︎ Назад',
} as const;

export const SERVICE_CATEGORY_TITLES: Record<ServiceCategoryKey, string> = { tattoo: 'Тату', piercing: 'Пирсинг', other: 'Другое' };
const SERVICE_CATEGORY_ORDER: ServiceCategoryKey[] = ['tattoo', 'piercing', 'other'];

/** One carousel page, or a menu (text with buttons). */
export interface CatalogPage {
  photo: PhotoSource | null;
  caption: string;
  keyboard: InlineKeyboard;
  /** Heading of the whole list («💎 Украшения для «Хеликс»»), stored in the chat history when it is opened. */
  heading: string;
  /** The position shown (clamped into the list) and the list length. */
  index: number;
  total: number;
}

export interface CatalogMenu {
  text: string;
  keyboard: InlineKeyboard;
}

const button = (text: string, action: CallbackAction): InlineButton => ({ text, data: encodeCallback(action) });

function rows<T>(items: T[], columns: number): T[][] {
  const result: T[][] = [];
  for (let i = 0; i < items.length; i += columns) result.push(items.slice(i, i + columns));
  return result;
}

const clamp = (index: number, total: number) => Math.min(Math.max(index, 0), total - 1);

/** «◀︎ 2 / 7 ▶︎» (wrapping around), nothing for a single item. */
function pager(index: number, total: number, page: (i: number) => CallbackAction): InlineButton[][] {
  if (total < 2) return [];
  return [
    [
      button('◀︎', page((index - 1 + total) % total)),
      button(`${index + 1} / ${total}`, { kind: 'noop' }),
      button('▶︎', page((index + 1) % total)),
    ],
  ];
}

// ── Jewelry ─────────────────────────────────────────────────────────────────────────────────────────────────────

const jewelryOrder = [asc(products.categorySort), asc(products.nameSort), asc(products.id)];

/** Active jewelry with a size in stock among `ids` (all of them when `ids` is undefined). */
function jewelryInStock(db: DbOrTx, ids?: number[]): ProductRow[] {
  if (ids !== undefined && ids.length === 0) return [];
  const conditions = [eq(products.kind, 'jewelry'), eq(products.active, true), hasSizeInStock];
  if (ids !== undefined) conditions.push(inArray(products.id, ids));
  return db.select().from(products).where(and(...conditions)).orderBy(...jewelryOrder).all();
}

/** Jewelry compatible with a service: active pieces linked to it (`product_services`) that have a size in stock. */
export function compatibleJewelry(db: DbOrTx, serviceId: number): ProductRow[] {
  const ids = db
    .select({ id: productServices.productId })
    .from(productServices)
    .where(eq(productServices.serviceId, serviceId))
    .all()
    .map((r) => r.id);
  return jewelryInStock(db, ids);
}

function jewelryCategoryRows(db: DbOrTx) {
  return db
    .select()
    .from(catalogCategories)
    .where(eq(catalogCategories.section, 'jewelry'))
    .orderBy(asc(catalogCategories.position), asc(catalogCategories.id))
    .all();
}

/** Jewelry categories that have pieces in stock, in staff order; `id: 0` — pieces without a (known) category. */
export function jewelryCategories(db: DbOrTx): Array<{ id: number; name: string; items: ProductRow[] }> {
  const all = jewelryInStock(db);
  const categories = jewelryCategoryRows(db);
  const known = new Set(categories.map((c) => c.name));
  const result = categories
    .map((c) => ({ id: c.id, name: c.name, items: all.filter((p) => p.category === c.name) }))
    .filter((c) => c.items.length > 0);
  const other = all.filter((p) => !p.category || !known.has(p.category));
  if (other.length > 0) result.push({ id: 0, name: result.length ? 'Другие' : 'Все украшения', items: other });
  return result;
}

function jewelryListItems(db: DbOrTx, list: JewelryList): { items: ProductRow[]; heading: string } | null {
  if (list.by === 'service') {
    const service = db.select().from(services).where(and(eq(services.id, list.id), eq(services.active, true))).get();
    if (!service) return null;
    return { items: compatibleJewelry(db, service.id), heading: `💎 Украшения для «${service.name}»` };
  }
  const category = jewelryCategories(db).find((c) => c.id === list.id);
  if (!category) return null;
  return { items: category.items, heading: `💎 ${category.name}` };
}

/** Sizes in stock with their prices: «• 6 мм — 1 500 ₽», or one price line for a piece without sizes. */
function stockLines(p: ProductRow, sizes: VariantRow[]): string[] {
  const named = sizes.filter((v) => v.name.trim());
  if (named.length === 0) {
    const price = sizes[0]?.price ?? p.price;
    return [`${formatRub(price)} · есть в наличии`];
  }
  return ['В наличии:', ...named.map((v) => `• ${v.name.trim()} — ${formatRub(v.price ?? p.price)}`)];
}

/** Carousel caption of a piece of jewelry: name, attributes, suitable zones, sizes in stock with prices. */
export function jewelryCardCaption(p: ProductRow, sizes: VariantRow[], suits: string[], heading: string | null): string {
  const attributes = [p.material, threadLabel(p.threadType), p.thicknessMm != null ? formatThickness(p.thicknessMm) : null, p.color, p.stone]
    .filter((x): x is string => Boolean(x && x.trim()))
    .join(' · ');
  const description = p.description?.trim();
  const lines = [
    ...(heading ? [heading, ''] : []),
    p.name,
    ...(attributes ? [attributes] : []),
    ...(suits.length ? [`Подходит для: ${suits.join(', ')}`] : []),
    ...(description ? [truncate(description, DESCRIPTION_MAX)] : []),
    '',
    ...stockLines(p, sizes),
  ];
  return truncate(lines.join('\n'), TELEGRAM_MAX_CAPTION);
}

function suitableServiceNames(db: DbOrTx, productId: number): string[] {
  const ids = serviceIdsByProduct(db, [productId]).get(productId) ?? [];
  if (ids.length === 0) return [];
  return db
    .select({ name: services.name })
    .from(services)
    .where(and(inArray(services.id, ids), eq(services.active, true)))
    .orderBy(asc(services.sort), asc(services.name))
    .all()
    .map((s) => s.name);
}

export function jewelryKeyboard(list: JewelryList, index: number, total: number, productId: number): InlineKeyboard {
  return [
    ...pager(index, total, (i) => ({ kind: 'jewelryPage', list, index: i })),
    [button(CATALOG_BUTTONS.want, { kind: 'jewelryWant', list, index, productId })],
    [button(CATALOG_BUTTONS.allJewelry, { kind: 'jewelryCategories' })],
  ];
}

/** Size buttons shown after «Хочу это украшение» when several sizes are in stock. */
export function sizeKeyboard(list: JewelryList, index: number, product: ProductRow, sizes: VariantRow[]): InlineKeyboard {
  return [
    ...sizes.map((v) => [button(`${v.name.trim()} — ${formatRub(v.price ?? product.price)}`, { kind: 'jewelrySize', list, index, variantId: v.id })]),
    [button(CATALOG_BUTTONS.back, { kind: 'jewelryPage', list, index })],
  ];
}

/** The page `index` of a jewelry carousel (clamped); null when the list is gone or empty. */
export function jewelryPage(db: DbOrTx, dataDir: string, list: JewelryList, index: number): (CatalogPage & { product: ProductRow }) | null {
  const found = jewelryListItems(db, list);
  if (!found || found.items.length === 0) return null;
  const total = found.items.length;
  const at = clamp(index, total);
  const product = found.items[at]!;
  const sizes = variantsByProduct(db, [product.id], { inStockOnly: true }).get(product.id) ?? [];
  return {
    product,
    photo: photoSourceFor(dataDir, product.photoUrl),
    caption: jewelryCardCaption(product, sizes, suitableServiceNames(db, product.id), found.heading),
    keyboard: jewelryKeyboard(list, at, total, product.id),
    heading: found.heading,
    index: at,
    total,
  };
}

export function jewelryCategoriesMenu(db: DbOrTx): CatalogMenu | null {
  const categories = jewelryCategories(db);
  if (categories.length === 0) return null;
  return {
    text: '💎 Украшения в наличии — выберите категорию. Покажу фото, размеры и цены.',
    keyboard: [
      ...rows(categories.map((c) => button(c.name, { kind: 'jewelryOpen', list: { by: 'category', id: c.id } })), MENU_COLUMNS),
      [button(CATALOG_BUTTONS.services, { kind: 'serviceCategories' })],
    ],
  };
}

// ── Services ────────────────────────────────────────────────────────────────────────────────────────────────────

export interface ServiceSection {
  list: ServiceList;
  title: string;
  items: ServiceRow[];
}

/**
 * Active services split into sections: per service category, its catalog categories in staff order (groups), then
 * the services without a known group («Пирсинг · прочее», or just «Тату» when the category has no groups).
 */
export function serviceSections(db: DbOrTx): ServiceSection[] {
  const active = db.select().from(services).where(eq(services.active, true)).orderBy(asc(services.sort), asc(services.name), asc(services.id)).all();
  const groups = db
    .select()
    .from(catalogCategories)
    .where(eq(catalogCategories.section, 'service'))
    .orderBy(asc(catalogCategories.position), asc(catalogCategories.id))
    .all();
  const sections: ServiceSection[] = [];
  for (const category of SERVICE_CATEGORY_ORDER) {
    const inCategory = active.filter((s) => s.category === category);
    if (inCategory.length === 0) continue;
    const own = groups.filter((g) => g.serviceCategory === category);
    const grouped = own
      .map((g) => ({ list: { category, groupId: g.id }, title: `${SERVICE_CATEGORY_TITLES[category]} · ${g.name}`, items: inCategory.filter((s) => s.groupName === g.name) }))
      .filter((g) => g.items.length > 0);
    const known = new Set(own.map((g) => g.name));
    const rest = inCategory.filter((s) => !s.groupName || !known.has(s.groupName));
    sections.push(...grouped);
    if (rest.length > 0) {
      const title = grouped.length ? `${SERVICE_CATEGORY_TITLES[category]} · прочее` : SERVICE_CATEGORY_TITLES[category];
      sections.push({ list: { category, groupId: 0 }, title, items: rest });
    }
  }
  return sections;
}

export function serviceKeyboard(db: DbOrTx, list: ServiceList, index: number, total: number, service: ServiceRow): InlineKeyboard {
  return [
    ...pager(index, total, (i) => ({ kind: 'servicePage', list, index: i })),
    [button(CATALOG_BUTTONS.book, { kind: 'serviceBook', serviceId: service.id })],
    ...(compatibleJewelry(db, service.id).length > 0
      ? [[button(CATALOG_BUTTONS.jewelryForService, { kind: 'serviceJewelry', serviceId: service.id })]]
      : []),
    [button(CATALOG_BUTTONS.allServices, { kind: 'serviceCategories' })],
  ];
}

export function servicePage(db: DbOrTx, dataDir: string, list: ServiceList, index: number): (CatalogPage & { service: ServiceRow }) | null {
  const section = serviceSections(db).find((s) => s.list.category === list.category && s.list.groupId === list.groupId);
  if (!section) return null;
  const total = section.items.length;
  const at = clamp(index, total);
  const service = section.items[at]!;
  const heading = `💉 ${section.title}`;
  return {
    service,
    photo: servicePhotoSource(dataDir, service),
    caption: truncate(`${heading}\n\n${serviceCaption(service)}`, TELEGRAM_MAX_CAPTION),
    keyboard: serviceKeyboard(db, list, at, total, service),
    heading,
    index: at,
    total,
  };
}

export function serviceSectionsMenu(db: DbOrTx): CatalogMenu | null {
  const sections = serviceSections(db);
  if (sections.length === 0) return null;
  return {
    text: '💉 Услуги и цены — выберите раздел. Покажу каждую услугу с ценой и вариантами.',
    keyboard: [
      ...rows(sections.map((s) => button(s.title, { kind: 'serviceOpen', list: s.list })), MENU_COLUMNS),
      ...(jewelryCategories(db).length > 0 ? [[button(CATALOG_BUTTONS.jewelry, { kind: 'jewelryCategories' })]] : []),
    ],
  };
}

// ── Delivery ────────────────────────────────────────────────────────────────────────────────────────────────────

/** Text stored in the chat history when a catalog is opened (staff and the AI see what the client was shown). */
export const catalogMessageText = (heading: string): string => `[Каталог] ${heading}`;

/** Sends a carousel page as a new message (the caption alone when there is no picture or it fails). */
export async function sendPage(ctx: AppContext, chatId: number, page: CatalogPage): Promise<boolean> {
  try {
    if (page.photo) {
      try {
        await ctx.gateway.sendPhoto(chatId, page.photo, page.caption, { keyboard: page.keyboard });
      } catch (err) {
        ctx.log.warn({ chatId, err: errorMessage(err) }, 'catalog photo failed, sending text');
        await ctx.gateway.sendText(chatId, page.caption, { keyboard: page.keyboard });
      }
    } else {
      await ctx.gateway.sendText(chatId, page.caption, { keyboard: page.keyboard });
    }
    storeMessage(ctx.db, chatId, 'assistant', catalogMessageText(page.heading));
    return true;
  } catch (err) {
    ctx.log.warn({ chatId, err: errorMessage(err) }, 'failed to send catalog');
    return false;
  }
}

export async function sendMenu(ctx: AppContext, chatId: number, menu: CatalogMenu): Promise<boolean> {
  try {
    await ctx.gateway.sendText(chatId, menu.text, { keyboard: menu.keyboard });
    storeMessage(ctx.db, chatId, 'assistant', catalogMessageText(menu.text));
    return true;
  } catch (err) {
    ctx.log.warn({ chatId, err: errorMessage(err) }, 'failed to send catalog menu');
    return false;
  }
}

/** The message a pressed button belongs to. */
export interface CurrentMessage {
  messageId: number;
  isPhoto: boolean;
}

/**
 * Shows `page` in place of the current message: the photo / text is edited when the kind matches; otherwise (a
 * piece without a photo after one with a photo, …) the message is replaced, as Telegram cannot turn one into the other.
 */
export async function showPageInPlace(ctx: AppContext, chatId: number, current: CurrentMessage, page: CatalogPage): Promise<void> {
  const { gateway } = ctx;
  if (page.photo && current.isPhoto) {
    try {
      await gateway.editPhoto(chatId, current.messageId, page.photo, page.caption, page.keyboard);
      return;
    } catch (err) {
      ctx.log.warn({ chatId, err: errorMessage(err) }, 'carousel photo edit failed, replacing the message');
    }
  } else if (!page.photo && !current.isPhoto) {
    await gateway.editText(chatId, current.messageId, page.caption, page.keyboard);
    return;
  }
  await gateway.deleteMessage(chatId, current.messageId).catch(() => undefined);
  if (page.photo) {
    try {
      await gateway.sendPhoto(chatId, page.photo, page.caption, { keyboard: page.keyboard });
      return;
    } catch (err) {
      ctx.log.warn({ chatId, err: errorMessage(err) }, 'carousel photo failed, sending text');
    }
  }
  await gateway.sendText(chatId, page.caption, { keyboard: page.keyboard });
}

/** Shows a menu in place of a text message, or as a new message under a photo. */
export async function showMenu(ctx: AppContext, chatId: number, current: CurrentMessage | null, menu: CatalogMenu): Promise<void> {
  if (current && !current.isPhoto) {
    await ctx.gateway.editText(chatId, current.messageId, menu.text, menu.keyboard);
    return;
  }
  await sendMenu(ctx, chatId, menu);
}
