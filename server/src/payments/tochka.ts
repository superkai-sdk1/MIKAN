import { X509Certificate } from 'node:crypto';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Agent, fetch, type Dispatcher } from 'undici';
import { z } from 'zod';
import type { Config } from '../config.js';
import { QrProviderError, type CreatedQr, type QrBankStatus, type QrProvider } from './qr-provider.js';

/**
 * Tochka's API certificate chains to the Russian Trusted Root CA (Минцифры), which Node does not trust.
 * Requests to Tochka trust exactly this root (pinned by fingerprint); nothing else in the process does.
 */
export const RUSSIAN_ROOT_CA_FILE = fileURLToPath(new URL('../../certs/russian-trusted-root-ca.pem', import.meta.url));
export const RUSSIAN_ROOT_CA_SHA256 =
  'D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31';
/** Tochka's BIC; the SBP lookup of a customer's merchants and accounts is keyed by it. */
export const TOCHKA_BANK_CODE = '044525104';

const REQUEST_TIMEOUT_MS = 15_000;
/** `payment-status` answer for a code that is known and readable. */
const CODE_OK = 'RQ00000';
/** The code is unknown — an unpaid code after expiry (a paid one stays readable for 24 h). */
const CODE_NOT_FOUND = 'RQ05014';

const errorBody = z.object({
  message: z.string().optional(),
  Errors: z.array(z.object({ message: z.string().optional() })).optional(),
});

const registerQrResponse = z.object({
  Data: z.object({ qrcId: z.string().min(1), payload: z.string() }),
});
const MAX_PAYLOAD_LENGTH = 2048;

const paymentEntry = z.object({
  qrcId: z.string(),
  code: z.string(),
  status: z.string().optional(),
  message: z.string().optional(),
});
type PaymentEntry = z.infer<typeof paymentEntry>;

const paymentStatusResponse = z.object({
  Data: z.object({ paymentList: z.array(paymentEntry) }),
});

const customersResponse = z.object({
  Data: z.object({
    Customer: z.array(z.object({ customerCode: z.string(), customerType: z.string(), shortName: z.string().optional() })),
  }),
});

const sbpCustomerResponse = z.object({
  Data: z.object({
    legalId: z.string(),
    name: z.string().optional(),
    MerchantList: z
      .array(z.object({ merchantId: z.string(), status: z.string(), brandName: z.string().optional(), capabilities: z.string() }))
      .default([]),
    AccountList: z.array(z.object({ accountId: z.string(), status: z.string() })).default([]),
  }),
});
export type SbpCustomer = z.infer<typeof sbpCustomerResponse>['Data'] & { customerCode: string };

/** Accepted → paid, Rejected → declined attempt; NotStarted / Received / InProgress → still waiting. */
export function bankStatusOf(entry: PaymentEntry): QrBankStatus {
  if (entry.code === CODE_NOT_FOUND) return 'pending';
  if (entry.code !== CODE_OK) throw new QrProviderError(`Tochka payment-status ${entry.code}: ${entry.message ?? ''}`);
  if (entry.status === 'Accepted') return 'paid';
  if (entry.status === 'Rejected') return 'rejected';
  return 'pending';
}

/** Whether an SBP merchant may issue one-off QR codes (`capabilities` is `static|dynamic|cashbox` flags, e.g. `011`). */
export const allowsDynamicQr = (capabilities: string): boolean => capabilities.length === 3 && capabilities[1] === '1';

/** Reads the bundled root and refuses anything but the one certificate with the pinned fingerprint. */
export function loadPinnedRootCa(file = RUSSIAN_ROOT_CA_FILE): string {
  const pem = fs.readFileSync(file, 'utf8');
  const blocks = pem.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) ?? [];
  if (blocks.length !== 1 || new X509Certificate(blocks[0]!).fingerprint256 !== RUSSIAN_ROOT_CA_SHA256) {
    throw new Error(`${file}: expected exactly the Russian Trusted Root CA (SHA-256 ${RUSSIAN_ROOT_CA_SHA256})`);
  }
  return blocks[0]!;
}

/** The QR must open the client's bank through NSPK for this very code, never an arbitrary link. */
export function assertNspkPayload(payload: string, qrcId: string): void {
  let url: URL | null = null;
  try {
    url = new URL(payload);
  } catch {
    // reported below
  }
  const ok = url && payload.length <= MAX_PAYLOAD_LENGTH && url.protocol === 'https:' && url.hostname === 'qr.nspk.ru' && url.pathname === `/${qrcId}`;
  if (!ok) throw new QrProviderError('Tochka register-qr: the payload is not an NSPK link for this code');
}

/** Thin JSON client for Tochka's Open API (`Authorization: Bearer <JWT>`). Never logs the token. */
export class TochkaClient {
  private readonly dispatcher: Dispatcher;

  constructor(
    private readonly options: { apiUrl: string; jwt: string },
    dispatcher?: Dispatcher,
  ) {
    this.dispatcher = dispatcher ?? new Agent({ connect: { ca: [loadPinnedRootCa()] } });
  }

  /** `operation` names the call in errors and logs instead of the path, which carries the account number. */
  async request<T>(operation: string, method: 'GET' | 'POST', path: string, schema: z.ZodType<T>, body?: unknown): Promise<T> {
    let response;
    try {
      response = await fetch(`${this.options.apiUrl}${path}`, {
        method,
        headers: {
          authorization: `Bearer ${this.options.jwt}`,
          accept: 'application/json',
          ...(body === undefined ? {} : { 'content-type': 'application/json' }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        redirect: 'error',
        dispatcher: this.dispatcher,
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (err) {
      const cause = (err as { cause?: { code?: string; message?: string } }).cause;
      throw new QrProviderError(`Tochka ${operation}: ${cause?.code ?? cause?.message ?? (err as Error).message}`);
    }
    const text = await response.text();
    let json: unknown;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      throw new QrProviderError(`Tochka ${operation}: HTTP ${response.status}, not JSON`, response.ok ? undefined : response.status);
    }
    if (!response.ok) {
      const parsed = errorBody.safeParse(json);
      const detail = parsed.success ? (parsed.data.Errors?.[0]?.message ?? parsed.data.message) : undefined;
      throw new QrProviderError(`Tochka ${operation}: HTTP ${response.status}${detail ? ` ${detail}` : ''}`, response.status);
    }
    const parsed = schema.safeParse(json);
    if (!parsed.success) throw new QrProviderError(`Tochka ${operation}: unexpected response shape`);
    return parsed.data;
  }

  /**
   * Every customer (company / sole proprietor) of the token with its SBP merchants and accounts, for setup.
   * Customers outside SBP are skipped; if none can be read, the bank's last error is thrown.
   */
  async sbpCustomers(): Promise<SbpCustomer[]> {
    const { Data } = await this.request('customers', 'GET', '/open-banking/v1.0/customers', customersResponse);
    const result: SbpCustomer[] = [];
    let lastError: unknown = null;
    for (const { customerCode } of Data.Customer) {
      try {
        const path = `/sbp/v1.0/customer/${encodeURIComponent(customerCode)}/${TOCHKA_BANK_CODE}`;
        const sbp = await this.request('sbp-customer', 'GET', path, sbpCustomerResponse);
        result.push({ ...sbp.Data, customerCode });
      } catch (err) {
        lastError = err;
      }
    }
    if (result.length === 0 && lastError instanceof QrProviderError) {
      throw new QrProviderError(`${lastError.message} — проверьте, что СБП подключена и у ключа есть права на СБП`, lastError.status);
    }
    return result;
  }
}

/** Dynamic SBP QR codes credited to one merchant (ТСП) and account. */
export class TochkaQrProvider implements QrProvider {
  readonly name = 'tochka';

  constructor(
    private readonly client: TochkaClient,
    private readonly merchantId: string,
    private readonly accountId: string,
  ) {}

  async createQr(input: { amount: number; purpose: string; ttlMinutes: number }): Promise<CreatedQr> {
    // accountId is `<account>/<BIC>`: its slash stays a path separator, as in Tochka's own examples.
    const path = `/sbp/v1.0/qr-code/merchant/${encodeURIComponent(this.merchantId)}/${this.accountId}`;
    const { Data } = await this.client.request('register-qr', 'POST', path, registerQrResponse, {
      Data: {
        amount: input.amount * 100,
        currency: 'RUB',
        paymentPurpose: input.purpose,
        qrcType: '02',
        ttl: input.ttlMinutes,
      },
    });
    assertNspkPayload(Data.payload, Data.qrcId);
    return { externalId: Data.qrcId, payload: Data.payload };
  }

  async paymentStatus(externalId: string): Promise<QrBankStatus> {
    const path = `/sbp/v1.0/qr-codes/${encodeURIComponent(externalId)}/payment-status`;
    const { Data } = await this.client.request('payment-status', 'GET', path, paymentStatusResponse);
    // Several entries per code (a declined attempt, then a paid one) must not hide the payment.
    const entries = Data.paymentList.filter((p) => p.qrcId === externalId);
    const entry = entries.find((p) => p.status === 'Accepted') ?? entries[0];
    // No entry means no operation on the code yet; a paid code stays listed as Accepted for 24 h.
    return entry ? bankStatusOf(entry) : 'pending';
  }
}

/** null unless the JWT, merchant and account are all configured. */
export function createQrProvider(config: Config['tochka']): QrProvider | null {
  if (!config.jwt || !config.merchantId || !config.accountId) return null;
  const client = new TochkaClient({ apiUrl: config.apiUrl, jwt: config.jwt });
  return new TochkaQrProvider(client, config.merchantId, config.accountId);
}
