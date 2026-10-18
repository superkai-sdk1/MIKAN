/** Texts about jewelry shared by the API, the bot and the reports (see docs/API.md → Product). */

export const THREAD_TYPES = ['internal', 'external', 'threadless'] as const;
export type ThreadType = (typeof THREAD_TYPES)[number];

const THREAD_LABELS: Record<ThreadType, string> = {
  internal: 'внутренняя резьба',
  external: 'внешняя резьба',
  threadless: 'безрезьбовое (push-pin)',
};

export function threadLabel(type: string | null): string | null {
  return type && type in THREAD_LABELS ? THREAD_LABELS[type as ThreadType] : null;
}

/** mm → American gauge, as piercers name thickness. */
const GAUGES: Array<[mm: number, gauge: number]> = [
  [0.8, 20], [1.0, 18], [1.2, 16], [1.6, 14], [2.0, 12], [2.5, 10],
  [3.2, 8], [4.0, 6], [5.0, 4], [6.0, 2], [8.0, 0],
];

/** «1.2 мм (16G)», «1.3 мм». */
export function formatThickness(mm: number): string {
  const text = `${Number(mm.toFixed(2))} мм`;
  const gauge = GAUGES.find(([value]) => Math.abs(value - mm) < 0.05)?.[1];
  return gauge === undefined ? text : `${text} (${gauge}G)`;
}

/** Name of a sold size: «Лабрет — 8 мм», just «Лабрет» for a product without sizes. */
export function sizedName(productName: string, variantName: string | null | undefined): string {
  const size = variantName?.trim();
  return size ? `${productName} — ${size}` : productName;
}
