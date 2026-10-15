/**
 * Schematic cover pictures for services, generated through the Polza AI Media API
 * (`POST {base}/v1/media`, then poll `GET {base}/v1/media/:id`). One shared style keeps the catalog consistent with
 * the printed MIKAN price lists: grey anatomical-reference drawings on white, no text.
 */

export const SERVICE_IMAGE_MODEL = 'openai/gpt-5.4-image-2';

const STYLE =
  'Clean schematic illustration for a tattoo and piercing studio price list. Monochrome: soft grey realistic shading ' +
  'with thin dark outlines on a pure white background, like an anatomical reference drawing. Calm, minimal, elegant. ' +
  'Centered subject with generous white margins. No text, no letters, no numbers, no logos, no watermark. Subject: ';

const CATEGORY_EN: Record<string, string> = { tattoo: 'tattoo', piercing: 'piercing', other: 'beauty' };

/** Full prompt for an English subject description. */
export function serviceImagePrompt(subject: string): string {
  return STYLE + subject.trim();
}

/** Subject for a service without a hand-written one: the studio's own name and description (in Russian). */
export function defaultImageSubject(service: { name: string; category: string; description: string | null }): string {
  const kind = CATEGORY_EN[service.category] ?? 'studio';
  const details = service.description?.trim() ? ` Details: ${service.description.trim()}` : '';
  return `the ${kind} studio service «${service.name}».${details}`;
}

export interface ImageGenConfig {
  apiKey: string;
  /** Polza API root, e.g. `https://polza.ai/api`. */
  baseUrl: string;
  model?: string;
  /** Overall limit for generation + download (every request is aborted at this deadline). */
  timeoutMs?: number;
  pollMs?: number;
  fetchImpl?: typeof fetch;
}

export interface GeneratedImage {
  data: Buffer;
  costRub: number | null;
}

export class ImageGenerationError extends Error {}

interface MediaJob {
  id?: string;
  status?: string;
  data?: { url?: string } | Array<{ url?: string }>;
  usage?: { cost_rub?: number };
  error?: unknown;
}

/** Overall limit for generation + download when the caller sets none. */
const DEFAULT_TIMEOUT_MS = 240_000;
/** Every request gets at least this long (capped by the overall timeout), even close to the deadline. */
const MIN_REQUEST_MS = 5_000;
/** The generated picture is downloaded into memory: refuse anything larger. */
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

const TOO_SLOW = 'Картинка генерируется слишком долго, попробуйте ещё раз';
const TOO_BIG = 'Сервис генерации вернул слишком большой файл (больше 10 МБ)';

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function resultUrl(job: MediaJob): string | undefined {
  return Array.isArray(job.data) ? job.data[0]?.url : job.data?.url;
}

function describe(error: unknown): string {
  if (typeof error === 'string') return error;
  if (error && typeof error === 'object' && 'message' in error) return String((error as { message: unknown }).message);
  return JSON.stringify(error ?? 'unknown');
}

/**
 * Runs one HTTP exchange (request + body) under an abort signal that fires at the overall deadline, but never
 * sooner than `floorMs` from now. Aborts become "too slow"; network failures become `ImageGenerationError`.
 */
async function withDeadline<T>(deadline: number, floorMs: number, run: (signal: AbortSignal) => Promise<T>): Promise<T> {
  const signal = AbortSignal.timeout(Math.max(deadline - Date.now(), floorMs, 1));
  try {
    return await run(signal);
  } catch (err) {
    if (signal.aborted) throw new ImageGenerationError(TOO_SLOW);
    if (err instanceof ImageGenerationError) throw err;
    throw new ImageGenerationError(`Не удалось связаться с сервисом генерации: ${describe(err)}`);
  }
}

/** Response JSON, or `{}` when the body is not JSON; rethrows when the read was aborted. */
async function readJob(res: Response, signal: AbortSignal): Promise<MediaJob> {
  try {
    return (await res.json()) as MediaJob;
  } catch (err) {
    if (signal.aborted) throw err;
    return {};
  }
}

/** Reads the body, aborting as soon as it exceeds `MAX_IMAGE_BYTES`. */
async function readCapped(res: Response): Promise<Buffer> {
  if (Number(res.headers.get('content-length')) > MAX_IMAGE_BYTES) throw new ImageGenerationError(TOO_BIG);
  if (!res.body) return Buffer.alloc(0);
  const reader = res.body.getReader();
  const chunks: Buffer[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_IMAGE_BYTES) {
      await reader.cancel().catch(() => undefined);
      throw new ImageGenerationError(TOO_BIG);
    }
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks, total);
}

function assertHttps(url: string): void {
  let protocol: string;
  try {
    protocol = new URL(url).protocol;
  } catch {
    throw new ImageGenerationError('Сервис генерации вернул некорректную ссылку на картинку');
  }
  if (protocol !== 'https:') throw new ImageGenerationError('Сервис генерации вернул небезопасную ссылку на картинку (не https)');
}

/** Generates one square picture and downloads it. Throws `ImageGenerationError` with a Russian message. */
export async function generateImage(config: ImageGenConfig, prompt: string): Promise<GeneratedImage> {
  const doFetch = config.fetchImpl ?? fetch;
  const base = config.baseUrl.replace(/\/+$/, '');
  const timeoutMs = config.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const deadline = Date.now() + timeoutMs;
  const floorMs = Math.min(MIN_REQUEST_MS, timeoutMs);
  const pollMs = config.pollMs ?? 4000;
  const headers = { Authorization: `Bearer ${config.apiKey}`, 'Content-Type': 'application/json' };

  const created = await withDeadline(deadline, floorMs, async (signal) => {
    const res = await doFetch(`${base}/v1/media`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        model: config.model ?? SERVICE_IMAGE_MODEL,
        input: { prompt, aspect_ratio: '1:1', n: 1 },
        async: true,
      }),
      signal,
    });
    return { ok: res.ok, status: res.status, job: await readJob(res, signal) };
  });
  let job = created.job;
  if (!created.ok) throw new ImageGenerationError(`Сервис генерации отказал (${created.status}): ${describe(job.error ?? job)}`);

  while (job.status === 'pending' || job.status === 'processing') {
    const id = job.id;
    if (!id) throw new ImageGenerationError('Сервис генерации не вернул номер задачи');
    await sleep(Math.min(pollMs, Math.max(0, deadline - Date.now())));
    if (Date.now() >= deadline) throw new ImageGenerationError(TOO_SLOW);
    const polled = await withDeadline(deadline, floorMs, async (signal) => {
      const res = await doFetch(`${base}/v1/media/${encodeURIComponent(id)}`, { headers, signal });
      return { ok: res.ok, status: res.status, job: await readJob(res, signal) };
    });
    if (!polled.ok) throw new ImageGenerationError(`Не удалось получить статус генерации (${polled.status})`);
    job = polled.job;
  }
  if (job.status !== 'completed') throw new ImageGenerationError(`Генерация не удалась: ${describe(job.error)}`);
  const url = resultUrl(job);
  if (!url) throw new ImageGenerationError('Сервис генерации не вернул картинку');
  assertHttps(url);

  // The CDN link is public: no credentials are sent with the download.
  const data = await withDeadline(deadline, floorMs, async (signal) => {
    const res = await doFetch(url, { signal });
    if (!res.ok) throw new ImageGenerationError(`Не удалось скачать картинку (${res.status})`);
    return readCapped(res);
  });
  return { data, costRub: job.usage?.cost_rub ?? null };
}
