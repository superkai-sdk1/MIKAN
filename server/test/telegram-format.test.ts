import { describe, expect, it } from 'vitest';
import { toPlainText, toTelegramHtml } from '../src/lib/telegram-format.js';

describe('Telegram formatting of bot messages', () => {
  it('renders bold, headings, list lines and code as Telegram HTML, escaping everything else', () => {
    const text = '## 📅 Записи сегодня\n- **10:00** Анна — Мочка\n* 12:00 Олег <друг> & Ко\nКод `A-12`, цена **1 600 ₽**.';
    expect(toTelegramHtml(text)).toBe(
      '<b>📅 Записи сегодня</b>\n• <b>10:00</b> Анна — Мочка\n• 12:00 Олег &lt;друг&gt; &amp; Ко\nКод <code>A-12</code>, цена <b>1 600 ₽</b>.',
    );
  });

  it('keeps unbalanced markers and plain text as they are', () => {
    expect(toTelegramHtml('5 ** 3 и *звёздочка*')).toBe('5 ** 3 и *звёздочка*');
    expect(toTelegramHtml('Просто текст 🙂')).toBe('Просто текст 🙂');
  });

  it('strips the markers for the plain fallback', () => {
    expect(toPlainText('# Итоги\n- **24 300 ₽** · 7 чеков\n`код`')).toBe('Итоги\n• 24 300 ₽ · 7 чеков\nкод');
  });
});
