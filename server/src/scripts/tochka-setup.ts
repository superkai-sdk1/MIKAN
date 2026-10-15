/**
 * Prints the SBP merchants (ТСП) and accounts available to TOCHKA_JWT, ready to paste into .env.
 * Needs only TOCHKA_JWT (and optionally TOCHKA_API_URL):
 *   docker compose exec api node dist/scripts/tochka-setup.js
 *   TOCHKA_JWT=… npx tsx src/scripts/tochka-setup.ts
 */
import { loadTochkaConfig } from '../config.js';
import { errorMessage } from '../lib/errors.js';
import { allowsDynamicQr, TochkaClient, type SbpCustomer } from '../payments/tochka.js';
import { isEntryPoint } from './cli.js';

export function describeSbpCustomers(customers: SbpCustomer[]): string {
  if (customers.length === 0) {
    return [
      'Компания не подключена к СБП.',
      'Подключите приём оплаты по QR-коду в интернет-банке Точки и запустите скрипт ещё раз.',
    ].join('\n');
  }
  const lines: string[] = [];
  for (const c of customers) {
    lines.push(`${c.name ?? c.legalId} (клиент ${c.customerCode})`);
    for (const m of c.MerchantList) {
      const notes = [m.brandName, m.status === 'Active' ? null : `статус ${m.status}`];
      if (!allowsDynamicQr(m.capabilities)) notes.push('не принимает динамические QR — нужна ТСП с capabilities 010/011/111');
      lines.push(`  TOCHKA_MERCHANT_ID=${m.merchantId}    # ${notes.filter(Boolean).join(', ')}`);
    }
    for (const a of c.AccountList) {
      lines.push(`  TOCHKA_ACCOUNT_ID=${a.accountId}${a.status === 'Active' ? '' : `    # статус ${a.status}`}`);
    }
  }
  return lines.join('\n');
}

async function main(): Promise<void> {
  const tochka = loadTochkaConfig();
  if (!tochka.jwt) throw new Error('Задайте TOCHKA_JWT в .env (интернет-банк Точки → Интеграции и API → JWT-ключ)');
  const client = new TochkaClient({ apiUrl: tochka.apiUrl, jwt: tochka.jwt });
  process.stdout.write(`${describeSbpCustomers(await client.sbpCustomers())}\n`);
}

if (isEntryPoint(import.meta.url)) {
  main().catch((err: unknown) => {
    process.stderr.write(`Ошибка: ${errorMessage(err)}\n`);
    process.exit(1);
  });
}
