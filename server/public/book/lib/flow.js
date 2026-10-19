// @ts-check
/**
 * The booking steps as a pure state machine. Every transition returns a new state; views read it and dispatch
 * actions. The catalog (services by id) is passed in where validity depends on it.
 */
import { isPhoneComplete } from './phone.js';
import { plainPriceText } from './format.js';

export const MAX_ITEMS = 5;
export const NAME_MAX = 100;
export const COMMENT_MAX = 500;
export const DEFAULT_DURATION_MIN = 60;

/** @typedef {'services' | 'master' | 'time' | 'contacts' | 'confirm'} Step */
/** @type {readonly Step[]} */
export const STEPS = Object.freeze(['services', 'master', 'time', 'contacts', 'confirm']);

export const STEP_TITLES = Object.freeze({
  services: 'Услуги',
  master: 'Мастер',
  time: 'Время',
  contacts: 'Контакты',
  confirm: 'Подтверждение',
});

/**
 * @typedef {{ serviceId: number, variant: string | null }} Item
 * @typedef {{ startsAt: string, masterIds: number[] }} Slot
 * @typedef {{ step: Step, items: Item[], master: number | 'any' | null, date: string | null, slot: Slot | null,
 *   name: string, phone: string, comment: string, website: string, linked: boolean }} FlowState
 */

/** @returns {FlowState} */
export function createFlow({ linked = false } = {}) {
  return {
    step: 'services',
    items: [],
    master: null,
    date: null,
    slot: null,
    name: '',
    phone: '',
    comment: '',
    website: '',
    linked,
  };
}

/** The steps this client goes through: a linked Telegram chat skips the contacts. */
export function stepsFor(state) {
  return state.linked ? STEPS.filter((step) => step !== 'contacts') : [...STEPS];
}

/** { index: 1-based, total } for «Шаг 2 из 5». */
export function stepPosition(state) {
  const steps = stepsFor(state);
  return { index: steps.indexOf(state.step) + 1, total: steps.length };
}

function itemValid(item, catalog) {
  const service = catalog.get(item.serviceId);
  if (!service) return false;
  const variants = service.variants ?? [];
  if (variants.length === 0) return item.variant === null;
  return variants.some((variant) => variant.name === item.variant);
}

/** Problems with the contacts, for the form: { name?, phone? } (empty when fine). */
export function contactErrors(state) {
  /** @type {{ name?: string, phone?: string }} */
  const errors = {};
  const name = state.name.trim();
  if (name.length === 0) errors.name = 'Напишите, как к вам обращаться';
  else if (name.length > NAME_MAX) errors.name = `Имя — не длиннее ${NAME_MAX} символов`;
  if (!isPhoneComplete(state.phone)) errors.phone = 'Введите номер полностью: +7 и 10 цифр';
  return errors;
}

/** Whether `step` itself is filled in. */
export function stepComplete(state, step, catalog) {
  switch (step) {
    case 'services':
      return state.items.length > 0 && state.items.length <= MAX_ITEMS && state.items.every((item) => itemValid(item, catalog));
    case 'master':
      return state.master !== null;
    case 'time':
      return state.slot !== null;
    case 'contacts':
      return state.linked || Object.keys(contactErrors(state)).length === 0;
    case 'confirm':
      return true;
    default:
      return false;
  }
}

/** Whether the current step lets the client go on. */
export function canProceed(state, catalog) {
  return stepComplete(state, state.step, catalog);
}

/** The first step that is not filled in yet (the furthest the client may jump to). */
export function firstIncompleteStep(state, catalog) {
  const steps = stepsFor(state);
  return steps.find((step) => !stepComplete(state, step, catalog)) ?? steps[steps.length - 1];
}

/** Whether `step` can be shown: every step before it is filled in. */
export function stepReachable(state, step, catalog) {
  const steps = stepsFor(state);
  const index = steps.indexOf(step);
  if (index < 0) return false;
  return steps.slice(0, index).every((earlier) => stepComplete(state, earlier, catalog));
}

function withoutSlot(state, changes) {
  return { ...state, ...changes, slot: null };
}

function toggleItem(state, { serviceId, variant = null }) {
  const existing = state.items.find((item) => item.serviceId === serviceId);
  if (existing) {
    const items = state.items.filter((item) => item.serviceId !== serviceId);
    return withoutSlot(state, { items });
  }
  if (state.items.length >= MAX_ITEMS) return state;
  return withoutSlot(state, { items: [...state.items, { serviceId, variant }] });
}

function setVariant(state, { serviceId, variant }) {
  if (!state.items.some((item) => item.serviceId === serviceId)) return state;
  const items = state.items.map((item) => (item.serviceId === serviceId ? { ...item, variant } : item));
  return withoutSlot(state, { items });
}

/**
 * The transitions.
 * @param {FlowState} state
 * @param {any} action `{ type, ...fields }`
 * @param {Map<number, any>} catalog
 * @returns {FlowState}
 */
export function reduce(state, action, catalog) {
  switch (action.type) {
    case 'toggleItem':
      return toggleItem(state, action);
    case 'setVariant':
      return setVariant(state, action);
    case 'setMaster':
      return action.master === state.master ? state : withoutSlot(state, { master: action.master });
    case 'setDate':
      return action.date === state.date ? state : withoutSlot(state, { date: action.date });
    case 'setSlot':
      return { ...state, slot: action.slot };
    case 'setField':
      if (!['name', 'phone', 'comment', 'website'].includes(action.field)) return state;
      return { ...state, [action.field]: String(action.value ?? '') };
    case 'setLinked': {
      const linked = Boolean(action.linked);
      const step = linked && state.step === 'contacts' ? 'confirm' : state.step;
      return { ...state, linked, step };
    }
    case 'next': {
      if (!canProceed(state, catalog)) return state;
      const steps = stepsFor(state);
      const next = steps[steps.indexOf(state.step) + 1];
      return next ? { ...state, step: next } : state;
    }
    case 'back': {
      const steps = stepsFor(state);
      const previous = steps[steps.indexOf(state.step) - 1];
      return previous ? { ...state, step: previous } : state;
    }
    case 'goto':
      return stepReachable(state, action.step, catalog) ? { ...state, step: action.step } : state;
    case 'slotTaken':
      return { ...state, step: 'time', slot: null };
    default:
      return state;
  }
}

/**
 * Applies `?service=&master=` to a new flow and jumps ahead over the steps that are already settled (a service
 * without variants → the master step; an active master too → the time step).
 * @param {FlowState} state
 * @param {{ serviceId: number | null, masterId: number | null }} preselect
 * @param {Map<number, any>} catalog
 * @param {Array<{ id: number }>} masters
 */
export function applyPreselect(state, preselect, catalog, masters) {
  let next = state;
  const service = preselect.serviceId !== null ? catalog.get(preselect.serviceId) : undefined;
  if (service) {
    const variants = service.variants ?? [];
    next = reduce(next, { type: 'toggleItem', serviceId: service.id, variant: variants[0]?.name ?? null }, catalog);
  }
  if (preselect.masterId !== null && masters.some((master) => master.id === preselect.masterId)) {
    next = reduce(next, { type: 'setMaster', master: preselect.masterId }, catalog);
  }
  // A service with variants stays on the first step so the client sees the options.
  if (!service || (service.variants ?? []).length > 0) return next;
  const target = firstIncompleteStep(next, catalog);
  const steps = stepsFor(next);
  const limit = steps.indexOf('time');
  const step = steps.indexOf(target) <= limit ? target : 'time';
  return { ...next, step };
}

/**
 * The chosen lines with their prices and durations (variant's, else the service's; 60 min when none).
 * @returns {Array<{ serviceId: number, name: string, price: number, priceText: string, durationMin: number, depositAmount: number }>}
 */
export function selectedLines(state, catalog) {
  return state.items.flatMap((item) => {
    const service = catalog.get(item.serviceId);
    if (!service) return [];
    const variant = item.variant ? (service.variants ?? []).find((v) => v.name === item.variant) : undefined;
    const price = variant?.price ?? service.price ?? 0;
    return [{
      serviceId: service.id,
      name: variant ? `${service.name} — ${variant.name}` : service.name,
      price,
      priceText: variant?.priceText ?? service.priceText ?? plainPriceText(price),
      durationMin: variant?.durationMin ?? service.durationMin ?? DEFAULT_DURATION_MIN,
      depositAmount: service.depositAmount ?? 0,
    }];
  });
}

/** Σ durations of the chosen lines. */
export function totalDuration(lines) {
  return lines.reduce((sum, line) => sum + line.durationMin, 0);
}

/** Σ prepayments of the chosen lines. */
export function totalDeposit(lines) {
  return lines.reduce((sum, line) => sum + line.depositAmount, 0);
}
