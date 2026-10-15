import { describe, expect, it } from 'vitest';
import {
  defaultImageSubject,
  generateImage,
  ImageGenerationError,
  MAX_IMAGE_BYTES,
  SERVICE_IMAGE_MODEL,
  serviceImagePrompt,
  type ImageGenConfig,
} from '../src/lib/service-images.js';

const PNG = Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), Buffer.alloc(8)]);
const TOO_SLOW = 'Картинка генерируется слишком долго, попробуйте ещё раз';
const TOO_BIG = 'Сервис генерации вернул слишком большой файл (больше 10 МБ)';

interface Call {
  url: string;
  init: RequestInit | undefined;
}
type Answer = Response | ((signal: AbortSignal) => Promise<Response>);

/** Fake fetch answering with the queued answers in order and recording every request. */
function fakeFetch(answers: Answer[]) {
  const calls: Call[] = [];
  const impl = (async (input: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(input), init });
    const next = answers.shift();
    if (!next) throw new Error(`unexpected request to ${String(input)}`);
    return typeof next === 'function' ? next(init!.signal!) : next;
  }) as typeof fetch;
  return { impl, calls };
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const completed = (url: string) => json({ status: 'completed', data: { url } });
const aborted = (signal: AbortSignal) =>
  new Promise<never>((_, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
/** A request that never answers until it is aborted. */
const hang = (signal: AbortSignal) => aborted(signal);
/** Headers arrive, but the body stalls until the request is aborted. */
const stalledBody = async (signal: AbortSignal) =>
  new Response(
    new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(PNG);
        signal.addEventListener('abort', () => controller.error(signal.reason), { once: true });
      },
    }),
  );
const config = (fetchImpl: typeof fetch, extra: Partial<ImageGenConfig> = {}): ImageGenConfig => ({
  apiKey: 'key-1',
  baseUrl: 'https://polza.test/api/',
  pollMs: 0,
  fetchImpl,
  ...extra,
});

describe('service image prompts', () => {
  it('wraps the subject in the shared schematic style', () => {
    const prompt = serviceImagePrompt('  a side view of an ear with a helix ring ');
    expect(prompt).toMatch(/^Clean schematic illustration/);
    expect(prompt).toContain('No text, no letters');
    expect(prompt.endsWith('Subject: a side view of an ear with a helix ring')).toBe(true);
  });

  it('derives a default subject from the service name, category and description', () => {
    expect(defaultImageSubject({ name: 'Септум', category: 'piercing', description: '  Прокол перегородки  ' })).toBe(
      'the piercing studio service «Септум». Details: Прокол перегородки',
    );
    expect(defaultImageSubject({ name: 'Тату', category: 'tattoo', description: null })).toBe('the tattoo studio service «Тату».');
    expect(defaultImageSubject({ name: 'Брови', category: 'other', description: '' })).toBe('the beauty studio service «Брови».');
  });
});

describe('generateImage (Polza Media API)', () => {
  it('creates an async job, polls it and downloads the picture', async () => {
    const { impl, calls } = fakeFetch([
      json({ id: 'job 1', status: 'pending' }),
      json({ id: 'job 1', status: 'processing' }),
      json({ id: 'job 1', status: 'completed', data: { url: 'https://cdn.test/img.png' }, usage: { cost_rub: 7.4 } }),
      new Response(PNG),
    ]);
    const result = await generateImage(config(impl), 'PROMPT');
    expect(result).toEqual({ data: PNG, costRub: 7.4 });

    expect(calls.map((c) => c.url)).toEqual([
      'https://polza.test/api/v1/media',
      'https://polza.test/api/v1/media/job%201',
      'https://polza.test/api/v1/media/job%201',
      'https://cdn.test/img.png',
    ]);
    const create = calls[0]!.init!;
    expect(create.method).toBe('POST');
    expect(create.headers).toMatchObject({ Authorization: 'Bearer key-1' });
    expect(JSON.parse(String(create.body))).toEqual({
      model: SERVICE_IMAGE_MODEL,
      input: { prompt: 'PROMPT', aspect_ratio: '1:1', n: 1 },
      async: true,
    });
    expect(calls[3]!.init).toEqual({ signal: expect.any(AbortSignal) }); // the CDN download carries no credentials
    expect(calls.every((c) => c.init?.signal instanceof AbortSignal)).toBe(true);
  });

  it('accepts an immediately completed job with an array result and a custom model', async () => {
    const { impl, calls } = fakeFetch([json({ status: 'completed', data: [{ url: 'https://cdn.test/a.jpg' }] }), new Response(PNG)]);
    expect(await generateImage(config(impl, { model: 'google/x' }), 'p')).toEqual({ data: PNG, costRub: null });
    expect(JSON.parse(String(calls[0]!.init!.body)).model).toBe('google/x');
  });

  it('throws ImageGenerationError with a Russian message on every failure', async () => {
    const cases: Array<[Answer[], string]> = [
      [[json({ error: { message: 'Insufficient balance' } }, 402)], 'Сервис генерации отказал (402): Insufficient balance'],
      [[json({ status: 'failed', error: 'content policy' })], 'Генерация не удалась: content policy'],
      [[json({ status: 'pending' })], 'Сервис генерации не вернул номер задачи'],
      [[json({ id: 'j', status: 'pending' }), json({}, 500)], 'Не удалось получить статус генерации (500)'],
      [[json({ status: 'completed', data: {} })], 'Сервис генерации не вернул картинку'],
      [[completed('https://cdn.test/x.png'), new Response('nope', { status: 404 })], 'Не удалось скачать картинку (404)'],
      [[], 'Не удалось связаться с сервисом генерации: unexpected request to https://polza.test/api/v1/media'],
    ];
    for (const [answers, message] of cases) {
      const { impl } = fakeFetch(answers);
      const promise = generateImage(config(impl), 'p');
      await expect(promise).rejects.toBeInstanceOf(ImageGenerationError);
      await expect(promise).rejects.toThrow(message);
    }
  });

  it('aborts every stalled request at the deadline and reports it as too slow', async () => {
    const stalls: Answer[][] = [
      [hang], // creating the job
      [json({ id: 'j', status: 'pending' }), hang], // polling
      [completed('https://cdn.test/x.png'), hang], // download headers
      [completed('https://cdn.test/x.png'), stalledBody], // download body
      [json({ id: 'j', status: 'processing' }), json({ id: 'j', status: 'processing' }), hang], // job outlives the deadline
    ];
    for (const answers of stalls) {
      const { impl } = fakeFetch(answers);
      const started = Date.now();
      await expect(generateImage(config(impl, { timeoutMs: 60, pollMs: 10 }), 'p')).rejects.toThrow(TOO_SLOW);
      expect(Date.now() - started).toBeLessThan(2000);
    }
  });

  it('downloads the picture only over https', async () => {
    for (const [url, message] of [
      ['http://cdn.test/x.png', 'Сервис генерации вернул небезопасную ссылку на картинку (не https)'],
      ['file:///etc/passwd', 'Сервис генерации вернул небезопасную ссылку на картинку (не https)'],
      ['not a url', 'Сервис генерации вернул некорректную ссылку на картинку'],
    ]) {
      const { impl, calls } = fakeFetch([completed(url!)]);
      await expect(generateImage(config(impl), 'p')).rejects.toThrow(message!);
      expect(calls).toHaveLength(1);
    }
  });

  it('refuses downloads over 10 MB by Content-Length or while streaming', async () => {
    const declared = new Response(PNG, { headers: { 'content-length': String(MAX_IMAGE_BYTES + 1) } });
    const { impl: byHeader } = fakeFetch([completed('https://cdn.test/x.png'), declared]);
    await expect(generateImage(config(byHeader), 'p')).rejects.toThrow(TOO_BIG);

    let pulled = 0;
    let cancelled = false;
    const chunk = new Uint8Array(1024 * 1024);
    const endless = new Response(
      new ReadableStream<Uint8Array>({
        pull(controller) {
          pulled += 1;
          controller.enqueue(chunk);
        },
        cancel() {
          cancelled = true;
        },
      }),
    );
    const { impl: byStream } = fakeFetch([completed('https://cdn.test/x.png'), endless]);
    await expect(generateImage(config(byStream), 'p')).rejects.toThrow(TOO_BIG);
    expect(cancelled).toBe(true);
    expect(pulled).toBeLessThanOrEqual(13);

    const exact = Buffer.alloc(MAX_IMAGE_BYTES, 1);
    const { impl: atLimit } = fakeFetch([completed('https://cdn.test/x.png'), new Response(exact)]);
    expect((await generateImage(config(atLimit), 'p')).data.length).toBe(MAX_IMAGE_BYTES);
  });
});
