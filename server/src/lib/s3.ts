import crypto from 'node:crypto';

/**
 * A minimal S3-compatible client (Yandex Object Storage, Selectel, Cloudflare R2, MinIO, AWS): put, list and delete
 * objects with path-style addressing and AWS Signature Version 4 — all the off-site backups need, without the SDK.
 */

export interface S3Config {
  /** `https://storage.yandexcloud.net` (no bucket in it). */
  endpoint: string;
  region: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
}

export interface SignInput {
  method: string;
  /** The URL as requested (path-style: `/<bucket>/<key>`). */
  url: URL;
  /** Headers to sign besides host / x-amz-date / x-amz-content-sha256. */
  headers?: Record<string, string>;
  payloadHash: string;
  /** `YYYYMMDDTHHMMSSZ` */
  amzDate: string;
}

export const sha256Hex = (data: string | Buffer): string => crypto.createHash('sha256').update(data).digest('hex');
const hmac = (key: Buffer | string, data: string): Buffer => crypto.createHmac('sha256', key).update(data).digest();

/** RFC 3986 encoding as SigV4 wants it (unreserved characters kept). */
const encode = (s: string): string =>
  encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

export const amzDateOf = (ms: number): string => new Date(ms).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');

/** The `Authorization` header and the headers it covers for one request. */
export function signRequest(config: Pick<S3Config, 'region' | 'accessKeyId' | 'secretAccessKey'>, input: SignInput) {
  const headers: Record<string, string> = {
    host: input.url.host,
    'x-amz-content-sha256': input.payloadHash,
    'x-amz-date': input.amzDate,
    ...Object.fromEntries(Object.entries(input.headers ?? {}).map(([k, v]) => [k.toLowerCase(), v.trim()])),
  };
  const names = Object.keys(headers).sort();
  const canonicalHeaders = names.map((n) => `${n}:${headers[n]}\n`).join('');
  const signedHeaders = names.join(';');
  const canonicalPath = input.url.pathname
    .split('/')
    .map((segment) => encode(decodeURIComponent(segment)))
    .join('/');
  const canonicalQuery = [...input.url.searchParams.entries()]
    .map(([k, v]) => [encode(k), encode(v)] as const)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${k}=${v}`)
    .join('&');
  const canonicalRequest = [input.method, canonicalPath, canonicalQuery, canonicalHeaders, signedHeaders, input.payloadHash].join('\n');
  const day = input.amzDate.slice(0, 8);
  const scope = `${day}/${config.region}/s3/aws4_request`;
  const stringToSign = ['AWS4-HMAC-SHA256', input.amzDate, scope, sha256Hex(canonicalRequest)].join('\n');
  const signingKey = hmac(hmac(hmac(hmac(`AWS4${config.secretAccessKey}`, day), config.region), 's3'), 'aws4_request');
  const signature = crypto.createHmac('sha256', signingKey).update(stringToSign).digest('hex');
  return {
    headers,
    authorization: `AWS4-HMAC-SHA256 Credential=${config.accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`,
  };
}

export class S3Error extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

export type Fetch = (url: string, init: { method: string; headers: Record<string, string>; body?: Buffer }) => Promise<Response>;

async function send(config: S3Config, method: string, url: URL, body: Buffer | undefined, fetchImpl: Fetch, now: number) {
  const payloadHash = sha256Hex(body ?? '');
  const { headers, authorization } = signRequest(config, { method, url, payloadHash, amzDate: amzDateOf(now) });
  const { host: _host, ...sent } = headers;
  const res = await fetchImpl(url.toString(), { method, headers: { ...sent, authorization }, ...(body ? { body } : {}) });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    const code = /<Code>([^<]+)<\/Code>/.exec(text)?.[1];
    throw new S3Error(`S3 ${method} ${url.pathname}: HTTP ${res.status}${code ? ` ${code}` : ''}`, res.status);
  }
  return res;
}

const objectUrl = (config: S3Config, key: string): URL =>
  new URL(`${config.endpoint.replace(/\/+$/, '')}/${encode(config.bucket)}/${key.split('/').map(encode).join('/')}`);

export async function putObject(config: S3Config, key: string, body: Buffer, fetchImpl: Fetch = fetch, now = Date.now()) {
  await send(config, 'PUT', objectUrl(config, key), body, fetchImpl, now);
}

export async function deleteObject(config: S3Config, key: string, fetchImpl: Fetch = fetch, now = Date.now()) {
  await send(config, 'DELETE', objectUrl(config, key), undefined, fetchImpl, now);
}

/** Keys under `prefix` (one page of up to 1000 is plenty for daily backups kept 30 days). */
export async function listKeys(config: S3Config, prefix: string, fetchImpl: Fetch = fetch, now = Date.now()): Promise<string[]> {
  const url = new URL(`${config.endpoint.replace(/\/+$/, '')}/${encode(config.bucket)}`);
  url.searchParams.set('list-type', '2');
  url.searchParams.set('prefix', prefix);
  const res = await send(config, 'GET', url, undefined, fetchImpl, now);
  const xml = await res.text();
  return [...xml.matchAll(/<Key>([^<]+)<\/Key>/g)].map((m) => m[1]!.replace(/&amp;/g, '&'));
}
