/**
 * Light Markdown of bot messages → Telegram (see docs/API.md «Formatting»): `**bold**`, heading lines `# …` (bold),
 * list lines `- …` / `* …` (as «• …») and `` `code` ``. Everything else is plain text.
 */

const HEADING = /^\s*#{1,6}\s+(.+?)\s*#*\s*$/;
const BULLET = /^(\s*)[-*]\s+(.*)$/;
const BOLD = /\*\*([^*\n]+?)\*\*/g;
const CODE = /`([^`\n]+)`/g;

const escapeHtml = (text: string): string => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** Line-level markers: a heading's text (without its markers) or a list line with «•». */
function lineParts(line: string): { heading: string | null; text: string } {
  const heading = HEADING.exec(line);
  if (heading) return { heading: heading[1]!.replace(BOLD, '$1'), text: '' };
  const bullet = BULLET.exec(line);
  return { heading: null, text: bullet ? `${bullet[1]}• ${bullet[2]}` : line };
}

/** HTML for Telegram's `parse_mode: 'HTML'`. */
export function toTelegramHtml(text: string): string {
  return text
    .split('\n')
    .map((line) => {
      const { heading, text: body } = lineParts(line);
      if (heading !== null) return `<b>${escapeHtml(heading.replace(CODE, '$1'))}</b>`;
      return escapeHtml(body).replace(CODE, '<code>$1</code>').replace(BOLD, '<b>$1</b>');
    })
    .join('\n');
}

/** The same text without markers: what is sent when Telegram rejects the markup. */
export function toPlainText(text: string): string {
  return text
    .split('\n')
    .map((line) => {
      const { heading, text: body } = lineParts(line);
      return (heading ?? body).replace(CODE, '$1').replace(BOLD, '$1');
    })
    .join('\n');
}
