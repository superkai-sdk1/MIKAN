// @ts-check
/** Step 2: a master or «Любой мастер». */
import { h } from '../lib/dom.js';
import { stepHeading } from './common.js';

const HEX_RE = /^#[0-9a-f]{6}$/i;

function initials(name) {
  return String(name).trim().split(/\s+/).slice(0, 2).map((word) => word[0] ?? '').join('').toUpperCase();
}

function avatar(master) {
  const el = h('span', { class: 'avatar', 'aria-hidden': 'true' }, initials(master.name));
  if (HEX_RE.test(master.color ?? '')) el.style.setProperty('--avatar', master.color);
  return el;
}

/**
 * @param {{ state: any, masters: Array<{ id: number, name: string, color: string | null }>,
 *   dispatch: (action: any) => void, haptic: () => void }} ctx
 */
export function renderMaster(ctx) {
  const options = [
    { value: 'any', name: 'Любой мастер', note: 'Покажем всё свободное время', icon: h('span', { class: 'avatar avatar-any', 'aria-hidden': 'true' }, '✦') },
    ...ctx.masters.map((master) => ({ value: master.id, name: master.name, note: '', icon: avatar(master) })),
  ];
  const radios = [];
  const list = h('div', { class: 'list', role: 'radiogroup', 'aria-label': 'Мастер' },
    options.map((option) => {
      const radio = /** @type {HTMLInputElement} */ (h('input', {
        type: 'radio', name: 'master', class: 'sr-only', value: String(option.value),
        onChange: () => {
          ctx.haptic();
          ctx.dispatch({ type: 'setMaster', master: option.value });
        },
      }));
      radios.push({ radio, value: option.value });
      return h('label', { class: 'card option' },
        radio,
        option.icon,
        h('span', { class: 'option-text' },
          h('span', { class: 'option-name' }, option.name),
          option.note ? h('span', { class: 'option-note' }, option.note) : null),
        h('span', { class: 'tick', 'aria-hidden': 'true' }));
    }));

  const node = h('section', { class: 'step' }, stepHeading('Выберите мастера'), list);

  function update(state) {
    radios.forEach(({ radio, value }) => {
      radio.checked = state.master === value;
      radio.closest('label')?.classList.toggle('selected', radio.checked);
    });
  }

  update(ctx.state);
  return { node, update };
}
