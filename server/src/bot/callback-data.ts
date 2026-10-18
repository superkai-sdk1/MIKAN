/**
 * Inline-button payloads (Telegram `callback_data`, at most 64 bytes). Everything a button needs is encoded in the
 * payload itself, so paging and choices work across server restarts without stored carousel state.
 */

export const TELEGRAM_MAX_CALLBACK_DATA = 64;

export type ServiceCategoryKey = 'tattoo' | 'piercing' | 'other';

/** A jewelry carousel: compatible pieces of a service, or the pieces of a jewelry category (0 = no category). */
export type JewelryList = { by: 'service'; id: number } | { by: 'category'; id: number };

/** A service carousel: the services of a catalog category (`groupId`, 0 = no group) inside a service category. */
export interface ServiceList {
  category: ServiceCategoryKey;
  groupId: number;
}

export type CallbackAction =
  /** The «2 / 7» counter. */
  | { kind: 'noop' }
  /** Sends a new jewelry carousel. */
  | { kind: 'jewelryOpen'; list: JewelryList }
  /** Turns the carousel this button belongs to to `index`. */
  | { kind: 'jewelryPage'; list: JewelryList; index: number }
  /** «Хочу это украшение»: size buttons when several sizes are in stock, otherwise the choice itself. */
  | { kind: 'jewelryWant'; list: JewelryList; index: number; productId: number }
  /** A size picked after «Хочу это украшение». */
  | { kind: 'jewelrySize'; list: JewelryList; index: number; variantId: number }
  /** «Все украшения» / `/catalog`: the jewelry categories. */
  | { kind: 'jewelryCategories' }
  | { kind: 'serviceOpen'; list: ServiceList }
  | { kind: 'servicePage'; list: ServiceList; index: number }
  /** «Записаться» on a service card. */
  | { kind: 'serviceBook'; serviceId: number }
  /** «Подходящие украшения» on a service card. */
  | { kind: 'serviceJewelry'; serviceId: number }
  /** «Все услуги»: the service sections. */
  | { kind: 'serviceCategories' }
  /** «✅ Приду» under a reminder. */
  | { kind: 'reminderConfirm'; appointmentId: number }
  /** «🔁 Перенести» under a reminder. */
  | { kind: 'reminderMove'; appointmentId: number };

const CATEGORY_LETTERS: Record<ServiceCategoryKey, string> = { tattoo: 't', piercing: 'p', other: 'o' };
const LETTER_CATEGORIES: Record<string, ServiceCategoryKey> = { t: 'tattoo', p: 'piercing', o: 'other' };

const jewelryKey = (list: JewelryList) => `${list.by === 'service' ? 's' : 'c'}${list.id}`;
const serviceKey = (list: ServiceList) => `${CATEGORY_LETTERS[list.category]}${list.groupId}`;

export function encodeCallback(action: CallbackAction): string {
  const data = (() => {
    switch (action.kind) {
      case 'noop':
        return 'x';
      case 'jewelryOpen':
        return `jo:${jewelryKey(action.list)}`;
      case 'jewelryPage':
        return `jp:${jewelryKey(action.list)}:${action.index}`;
      case 'jewelryWant':
        return `jw:${jewelryKey(action.list)}:${action.index}:${action.productId}`;
      case 'jewelrySize':
        return `jz:${jewelryKey(action.list)}:${action.index}:${action.variantId}`;
      case 'jewelryCategories':
        return 'jc';
      case 'serviceOpen':
        return `so:${serviceKey(action.list)}`;
      case 'servicePage':
        return `sp:${serviceKey(action.list)}:${action.index}`;
      case 'serviceBook':
        return `sb:${action.serviceId}`;
      case 'serviceJewelry':
        return `sj:${action.serviceId}`;
      case 'serviceCategories':
        return 'sc';
      case 'reminderConfirm':
        return `rc:${action.appointmentId}`;
      case 'reminderMove':
        return `rm:${action.appointmentId}`;
    }
  })();
  if (Buffer.byteLength(data) > TELEGRAM_MAX_CALLBACK_DATA) throw new Error(`callback data too long: ${data}`);
  return data;
}

const ID = /^\d{1,12}$/;
const int = (value: string | undefined): number | null => (value !== undefined && ID.test(value) ? Number(value) : null);

function parseJewelryKey(value: string | undefined): JewelryList | null {
  const match = value ? /^([sc])(\d{1,12})$/.exec(value) : null;
  if (!match) return null;
  return { by: match[1] === 's' ? 'service' : 'category', id: Number(match[2]) };
}

function parseServiceKey(value: string | undefined): ServiceList | null {
  const match = value ? /^([tpo])(\d{1,12})$/.exec(value) : null;
  if (!match) return null;
  return { category: LETTER_CATEGORIES[match[1]!]!, groupId: Number(match[2]) };
}

/** The action of a button payload; null for anything unknown or malformed (old or forged buttons). */
export function decodeCallback(data: string): CallbackAction | null {
  const [tag, a, b, c, ...rest] = data.split(':');
  if (rest.length > 0) return null;
  switch (tag) {
    case 'x':
      return a === undefined ? { kind: 'noop' } : null;
    case 'jc':
      return a === undefined ? { kind: 'jewelryCategories' } : null;
    case 'sc':
      return a === undefined ? { kind: 'serviceCategories' } : null;
    case 'jo': {
      const list = parseJewelryKey(a);
      return list && b === undefined ? { kind: 'jewelryOpen', list } : null;
    }
    case 'jp': {
      const list = parseJewelryKey(a);
      const index = int(b);
      return list && index !== null && c === undefined ? { kind: 'jewelryPage', list, index } : null;
    }
    case 'jw':
    case 'jz': {
      const list = parseJewelryKey(a);
      const index = int(b);
      const id = int(c);
      if (!list || index === null || id === null) return null;
      return tag === 'jw' ? { kind: 'jewelryWant', list, index, productId: id } : { kind: 'jewelrySize', list, index, variantId: id };
    }
    case 'so': {
      const list = parseServiceKey(a);
      return list && b === undefined ? { kind: 'serviceOpen', list } : null;
    }
    case 'sp': {
      const list = parseServiceKey(a);
      const index = int(b);
      return list && index !== null && c === undefined ? { kind: 'servicePage', list, index } : null;
    }
    case 'sb':
    case 'sj':
    case 'rc':
    case 'rm': {
      const id = int(a);
      if (id === null || b !== undefined) return null;
      if (tag === 'sb') return { kind: 'serviceBook', serviceId: id };
      if (tag === 'sj') return { kind: 'serviceJewelry', serviceId: id };
      if (tag === 'rc') return { kind: 'reminderConfirm', appointmentId: id };
      return { kind: 'reminderMove', appointmentId: id };
    }
    default:
      return null;
  }
}
