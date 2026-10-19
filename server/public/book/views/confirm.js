// @ts-check
/** Step 5: everything chosen, with «Изменить» links, the prepayment and cancellation rules, and the booking error. */
import { h, mount } from '../lib/dom.js';
import { selectedLines, totalDeposit, totalDuration } from '../lib/flow.js';
import { formatDateTime, formatDuration, formatRub, formatTime, totalPriceText } from '../lib/format.js';
import { errorPanel, stepHeading, summaryRow } from './common.js';

/**
 * @param {{ state: any, catalog: Map<number, any>, masters: Array<{ id: number, name: string }>, config: any,
 *   me: { name: string, phone: string } | null, timeZone: string, edit: (step: string) => void }} ctx
 */
export function renderConfirm(ctx) {
  const { state, catalog, config } = ctx;
  const lines = selectedLines(state, catalog);
  const duration = totalDuration(lines);
  const deposit = totalDeposit(lines);
  const masterName = state.master === 'any'
    ? 'Любой свободный мастер'
    : ctx.masters.find((m) => m.id === state.master)?.name ?? 'Мастер';
  const startsAt = state.slot?.startsAt;
  const endsAt = startsAt ? new Date(Date.parse(startsAt) + duration * 60_000).toISOString() : null;
  const edit = (step, what) => ({ onClick: () => ctx.edit(step), ariaLabel: `Изменить ${what}` });

  const servicesValue = h('ul', { class: 'lines' }, lines.map((line) =>
    h('li', null, h('span', null, line.name), h('span', { class: 'line-price' }, line.priceText))));

  const contactsValue = state.linked
    ? h('span', null, [ctx.me?.name, ctx.me?.phone].filter(Boolean).join(', '), h('span', { class: 'muted' }, ' — из Telegram'))
    : h('span', null, `${state.name.trim()}, ${state.phone}`);

  const card = h('div', { class: 'card summary' },
    summaryRow('Услуги', servicesValue, edit('services', 'услуги')),
    summaryRow('Мастер', masterName, edit('master', 'мастера')),
    summaryRow('Когда',
      startsAt ? `${formatDateTime(startsAt, ctx.timeZone)}–${formatTime(/** @type {string} */ (endsAt), ctx.timeZone)}` : '',
      edit('time', 'время')),
    summaryRow('Контакты', contactsValue, state.linked ? null : edit('contacts', 'контакты')),
    state.comment.trim() ? summaryRow('Комментарий', state.comment.trim(), edit('contacts', 'комментарий')) : null,
    h('div', { class: 'summary-total' },
      h('span', null, `Итого · ${formatDuration(duration)}`),
      h('span', { class: 'total-price' }, totalPriceText(lines))));

  const notes = [
    deposit > 0
      ? h('div', { class: 'panel panel-accent' },
        h('p', { class: 'panel-title' }, `Предоплата ${formatRub(deposit)}`),
        h('p', { class: 'panel-text' }, 'Сразу после записи подскажем, как её внести. Она войдёт в стоимость, остальное — в студии.'))
      : h('p', { class: 'muted' }, 'Предоплата не нужна. Студия подтвердит запись в ближайшее время.'),
    config.note ? h('div', { class: 'panel' }, h('p', { class: 'panel-text' }, config.note)) : null,
    config.cancellationText ? h('p', { class: 'muted small' }, config.cancellationText) : null,
    h('p', { class: 'muted small' }, 'Нажимая «Записаться», вы соглашаетесь, что студия обработает ваши имя и телефон для записи.'),
  ];

  const errorSlot = h('div', { class: 'error-slot' });
  const node = h('section', { class: 'step' }, stepHeading('Проверьте запись'), errorSlot, card, notes);

  return {
    node,
    update: () => undefined,
    /** @param {{ title: string, message: string }} description @param {Array<{ label: string, onClick: () => void, primary?: boolean }>} actions */
    showError(description, actions) {
      mount(errorSlot, errorPanel(description, actions));
      errorSlot.scrollIntoView?.({ block: 'start', behavior: 'smooth' });
    },
    clearError() {
      mount(errorSlot);
    },
  };
}
