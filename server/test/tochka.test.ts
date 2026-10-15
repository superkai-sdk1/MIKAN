import { X509Certificate } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { MockAgent } from 'undici';
import { describe, expect, it } from 'vitest';
import { QrProviderError } from '../src/payments/qr-provider.js';
import { loadTochkaConfig } from '../src/config.js';
import {
  allowsDynamicQr,
  assertNspkPayload,
  bankStatusOf,
  createQrProvider,
  loadPinnedRootCa,
  RUSSIAN_ROOT_CA_FILE,
  RUSSIAN_ROOT_CA_SHA256,
  TochkaClient,
  TochkaQrProvider,
} from '../src/payments/tochka.js';
import { describeSbpCustomers } from '../src/scripts/tochka-setup.js';
import { testConfig } from './helpers.js';

const ORIGIN = 'https://tochka.test';
const ACCOUNT = '40702810123456789012/044525104';
const QRC_ID = 'AD10001B38T99KA99CD8S37FMTH8CFQ7';

function setup() {
  const agent = new MockAgent();
  agent.disableNetConnect();
  const pool = agent.get(ORIGIN);
  const client = new TochkaClient({ apiUrl: `${ORIGIN}/uapi`, jwt: 'test.jwt.token' }, agent);
  return { pool, client, provider: new TochkaQrProvider(client, 'MA0000086825', ACCOUNT) };
}

const statusReply = (status: string | undefined, code = 'RQ00000') => ({
  Data: { paymentList: [{ qrcId: QRC_ID, code, ...(status ? { status } : {}), message: 'Запрос обработан успешно' }] },
});

describe('Tochka SBP client', () => {
  it('registers a dynamic QR in kopecks on the merchant and account', async () => {
    const { pool, provider } = setup();
    let sent: unknown;
    pool
      .intercept({
        path: `/uapi/sbp/v1.0/qr-code/merchant/MA0000086825/${ACCOUNT}`,
        method: 'POST',
        headers: { authorization: 'Bearer test.jwt.token', 'content-type': 'application/json' },
        body: (body: string) => {
          sent = JSON.parse(body);
          return true;
        },
      })
      .reply(200, {
        Data: { payload: `https://qr.nspk.ru/${QRC_ID}?type=02&bank=100000000065&sum=150000&cur=RUB&crc=43B6`, qrcId: QRC_ID },
      });

    const qr = await provider.createQr({ amount: 1500, purpose: 'Оплата услуг, MIKAN STUDIO', ttlMinutes: 10 });

    expect(sent).toEqual({
      Data: { amount: 150_000, currency: 'RUB', paymentPurpose: 'Оплата услуг, MIKAN STUDIO', qrcType: '02', ttl: 10 },
    });
    expect(qr).toEqual({ externalId: QRC_ID, payload: `https://qr.nspk.ru/${QRC_ID}?type=02&bank=100000000065&sum=150000&cur=RUB&crc=43B6` });
  });

  it('accepts only an NSPK link for the registered code', async () => {
    expect(() => assertNspkPayload(`https://qr.nspk.ru/${QRC_ID}?type=02&sum=150000&cur=RUB`, QRC_ID)).not.toThrow();
    for (const bad of [
      `https://evil.example/${QRC_ID}`,
      `http://qr.nspk.ru/${QRC_ID}`,
      `https://qr.nspk.ru/AD000000000000000000000000000000`,
      'javascript:alert(1)',
      'not a url',
      `https://qr.nspk.ru/${QRC_ID}?${'x'.repeat(3000)}`,
    ]) {
      expect(() => assertNspkPayload(bad, QRC_ID), bad.slice(0, 40)).toThrow(QrProviderError);
    }

    const { pool, provider } = setup();
    pool.intercept({ path: `/uapi/sbp/v1.0/qr-code/merchant/MA0000086825/${ACCOUNT}`, method: 'POST' }).reply(200, {
      Data: { payload: 'https://pay.example/steal', qrcId: QRC_ID },
    });
    await expect(provider.createQr({ amount: 100, purpose: 'x', ttlMinutes: 10 })).rejects.toThrow(/not an NSPK link/);
  });

  it('never puts the account number into errors', async () => {
    const { pool, provider } = setup();
    pool.intercept({ path: `/uapi/sbp/v1.0/qr-code/merchant/MA0000086825/${ACCOUNT}`, method: 'POST' }).reply(400, {
      Errors: [{ message: 'amount must be positive' }],
    });
    const err = await provider.createQr({ amount: 100, purpose: 'x', ttlMinutes: 10 }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(QrProviderError);
    expect((err as QrProviderError).message).toBe('Tochka register-qr: HTTP 400 amount must be positive');
    expect((err as QrProviderError).status).toBe(400);
  });

  it('maps payment statuses: Accepted is paid, Rejected is declined, the rest is waiting', async () => {
    const { pool, provider } = setup();
    const path = `/uapi/sbp/v1.0/qr-codes/${QRC_ID}/payment-status`;
    pool.intercept({ path, method: 'GET' }).reply(200, statusReply('Accepted'));
    pool.intercept({ path, method: 'GET' }).reply(200, statusReply('InProgress'));
    pool.intercept({ path, method: 'GET' }).reply(200, { Data: { paymentList: [] } });
    pool.intercept({ path, method: 'GET' }).reply(200, {
      Data: { paymentList: [{ qrcId: QRC_ID, code: 'RQ00000', status: 'Rejected' }, { qrcId: QRC_ID, code: 'RQ00000', status: 'Accepted' }] },
    });
    expect(await provider.paymentStatus(QRC_ID)).toBe('paid');
    expect(await provider.paymentStatus(QRC_ID)).toBe('pending');
    expect(await provider.paymentStatus(QRC_ID), 'no operation on the code yet').toBe('pending');
    expect(await provider.paymentStatus(QRC_ID), 'a later paid attempt wins over a declined one').toBe('paid');

    const entry = (status?: string, code = 'RQ00000') => ({ qrcId: QRC_ID, code, status });
    expect(bankStatusOf(entry('NotStarted'))).toBe('pending');
    expect(bankStatusOf(entry('Received'))).toBe('pending');
    expect(bankStatusOf(entry('Rejected'))).toBe('rejected');
    expect(bankStatusOf(entry(undefined, 'RQ05014')), 'expired unpaid code is no longer found').toBe('pending');
    expect(() => bankStatusOf(entry(undefined, 'RQ05099'))).toThrow(QrProviderError);
  });

  it('turns HTTP and network failures into QrProviderError with the bank message', async () => {
    const { pool, provider } = setup();
    pool.intercept({ path: `/uapi/sbp/v1.0/qr-codes/${QRC_ID}/payment-status`, method: 'GET' }).reply(403, {
      code: '403',
      message: 'Что-то пошло не так',
      Errors: [{ errorCode: 'Something going wrong', message: 'Forbidden by consent' }],
    });
    await expect(provider.paymentStatus(QRC_ID)).rejects.toThrow(/HTTP 403 Forbidden by consent/);

    pool.intercept({ path: `/uapi/sbp/v1.0/qr-codes/${QRC_ID}/payment-status`, method: 'GET' }).reply(502, '<html>Bad gateway</html>');
    await expect(provider.paymentStatus(QRC_ID)).rejects.toThrow(/HTTP 502, not JSON/);

    pool.intercept({ path: `/uapi/sbp/v1.0/qr-codes/${QRC_ID}/payment-status`, method: 'GET' }).replyWithError(new Error('socket hang up'));
    await expect(provider.paymentStatus(QRC_ID)).rejects.toThrow(QrProviderError);

    pool.intercept({ path: `/uapi/sbp/v1.0/qr-codes/${QRC_ID}/payment-status`, method: 'GET' }).reply(200, { Data: {} });
    await expect(provider.paymentStatus(QRC_ID)).rejects.toThrow(/unexpected response shape/);
  });

  it('lists SBP merchants and accounts for setup, skipping customers outside SBP', async () => {
    const { pool, client } = setup();
    pool.intercept({ path: '/uapi/open-banking/v1.0/customers', method: 'GET' }).reply(200, {
      Data: {
        Customer: [
          { customerCode: '300000092', customerType: 'Business' },
          { customerCode: '1234567ab', customerType: 'Personal' },
        ],
      },
    });
    pool.intercept({ path: '/uapi/sbp/v1.0/customer/300000092/044525104', method: 'GET' }).reply(200, {
      Data: {
        legalId: 'LA0000008089',
        name: 'ИП Микан',
        MerchantList: [
          { merchantId: 'MA0000086825', status: 'Active', brandName: 'MIKAN STUDIO', capabilities: '011' },
          { merchantId: 'MA0000000002', status: 'Active', brandName: 'Касса', capabilities: '100' },
        ],
        AccountList: [{ accountId: ACCOUNT, status: 'Active' }],
      },
    });
    pool.intercept({ path: '/uapi/sbp/v1.0/customer/1234567ab/044525104', method: 'GET' }).reply(403, { message: 'Forbidden by consent' });

    const customers = await client.sbpCustomers();

    expect(customers).toHaveLength(1);
    expect(describeSbpCustomers(customers)).toBe(
      [
        'ИП Микан (клиент 300000092)',
        '  TOCHKA_MERCHANT_ID=MA0000086825    # MIKAN STUDIO',
        '  TOCHKA_MERCHANT_ID=MA0000000002    # Касса, не принимает динамические QR — нужна ТСП с capabilities 010/011/111',
        `  TOCHKA_ACCOUNT_ID=${ACCOUNT}`,
      ].join('\n'),
    );
    expect(describeSbpCustomers([])).toMatch(/^Компания не подключена к СБП/);
  });

  it('explains a key without SBP rights instead of reporting no SBP', async () => {
    const { pool, client } = setup();
    pool.intercept({ path: '/uapi/open-banking/v1.0/customers', method: 'GET' }).reply(200, {
      Data: { Customer: [{ customerCode: '304739396', customerType: 'Business' }] },
    });
    pool.intercept({ path: '/uapi/sbp/v1.0/customer/304739396/044525104', method: 'GET' }).reply(403, {
      Errors: [{ message: 'Forbidden by consent' }],
    });
    await expect(client.sbpCustomers()).rejects.toThrow('Tochka sbp-customer: HTTP 403 Forbidden by consent — проверьте, что СБП подключена и у ключа есть права на СБП');
  });

  it('reads dynamic QR capability flags', () => {
    expect(['010', '011', '111'].map(allowsDynamicQr)).toEqual([true, true, true]);
    expect(['001', '100', '101', ''].map(allowsDynamicQr)).toEqual([false, false, false, false]);
  });

  it('pins the Russian Trusted Root CA used for Tochka TLS', () => {
    const pem = loadPinnedRootCa();
    const cert = new X509Certificate(pem);
    expect(cert.subject).toContain('CN=Russian Trusted Root CA');
    expect(cert.fingerprint256).toBe(RUSSIAN_ROOT_CA_SHA256);

    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mikan-ca-'));
    try {
      const doubled = path.join(dir, 'doubled.pem');
      fs.writeFileSync(doubled, `${pem}\n${pem}\n`);
      expect(() => loadPinnedRootCa(doubled), 'an appended certificate is refused').toThrow(/expected exactly/);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
    expect(fs.readFileSync(RUSSIAN_ROOT_CA_FILE, 'utf8')).toContain('BEGIN CERTIFICATE');
  });
});

describe('Tochka configuration', () => {
  it('enables QR payments only with the JWT, merchant and account', () => {
    expect(createQrProvider(testConfig().tochka)).toBeNull();
    expect(createQrProvider(testConfig({ TOCHKA_JWT: 'jwt' }).tochka)).toBeNull();
    const full = testConfig({ TOCHKA_JWT: 'jwt', TOCHKA_MERCHANT_ID: 'MA0000086825', TOCHKA_ACCOUNT_ID: ACCOUNT });
    expect(full.tochka.apiUrl).toBe('https://enter.tochka.com/uapi');
    expect(createQrProvider(full.tochka)?.name).toBe('tochka');
  });

  it('rejects an account without the BIC, a merchant id with junk and a plain-http API', () => {
    expect(() => testConfig({ TOCHKA_ACCOUNT_ID: '40702810123456789012' })).toThrow(/TOCHKA_ACCOUNT_ID: ожидается «счёт\/БИК»/);
    expect(() => testConfig({ TOCHKA_MERCHANT_ID: 'MA00/../x' })).toThrow(/TOCHKA_MERCHANT_ID/);
    expect(() => testConfig({ TOCHKA_API_URL: 'http://enter.tochka.com/uapi' })).toThrow(/TOCHKA_API_URL: нужен https/);
  });

  it('loads the Tochka settings alone for the setup script', () => {
    expect(loadTochkaConfig({ TOCHKA_JWT: 'jwt', TOCHKA_API_URL: 'https://enter.tochka.com/sandbox/v2/' })).toEqual({
      apiUrl: 'https://enter.tochka.com/sandbox/v2',
      jwt: 'jwt',
      merchantId: null,
      accountId: null,
    });
  });
});
