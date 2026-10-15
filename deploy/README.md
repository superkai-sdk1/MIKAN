# MIKAN STUDIO — эксплуатация сервера

Сервер: `ssh mikan`, каталог `/opt/mikan`:

```
/opt/mikan/server/          исходники API (собираются в Docker)
/opt/mikan/deploy/          docker-compose.yml, Caddyfile, .env, data/
/opt/mikan/deploy/data/     mikan.db, uploads/ (фото), backups/ (ежедневные копии БД)
```

Стек: контейнер `api` (Node.js, порт 3000 только внутри сети Docker) и `caddy` (80/443, автоматический HTTPS, проксирует на `api`).

## Первый запуск

1. На сервере должны быть Docker и плагин `docker compose`.
2. Создайте `.env` (один раз, деплой его не перезаписывает):
   ```bash
   ssh mikan 'mkdir -p /opt/mikan/deploy'
   scp deploy/.env.example mikan:/opt/mikan/deploy/.env
   ssh mikan 'nano /opt/mikan/deploy/.env'
   ```
   Обязательно: `JWT_SECRET` (`openssl rand -hex 32`), `ADMIN_PASSWORD`, `TELEGRAM_BOT_TOKEN`,
   `TELEGRAM_API_ROOT` (адрес Cloudflare Worker — Telegram с сервера заблокирован), `AI_API_KEY` (Polza).
3. Запустите `deploy/deploy.sh` со своего компьютера.
4. Войдите в приложение логином `ADMIN_LOGIN` / паролем `ADMIN_PASSWORD` и смените пароль.
5. Уведомления персоналу: в приложении «Настройки → Бот → код для рабочего чата», добавьте бота
   в рабочую группу Telegram и отправьте там `/staff <код>` (код действует 15 минут).

## Деплой обновлений

```bash
deploy/deploy.sh
```

Скрипт синхронизирует `server/` и `deploy/` (без `node_modules`, `data/`, `.env`), пересобирает образ,
перезапускает контейнеры и ждёт `/api/health`. Миграции БД применяются автоматически при старте.

## Логи и состояние

```bash
ssh mikan 'cd /opt/mikan/deploy && docker compose ps'
ssh mikan 'cd /opt/mikan/deploy && docker compose logs -f --tail=200 api'
ssh mikan 'cd /opt/mikan/deploy && docker compose logs --tail=100 caddy'
curl https://95-170-124-192.sslip.io/api/health
```

Перезапуск: `docker compose restart api`. Остановка: `docker compose down` (данные в `data/` сохраняются).

## Резервные копии

- Автоматически: каждый день после 04:00 по времени студии (часовой пояс из настроек студии)
  в `data/backups/mikan-ГГГГ-ММ-ДД.db`, хранятся последние 14.
- Скачать копию к себе:
  ```bash
  scp mikan:/opt/mikan/deploy/data/backups/mikan-2026-10-15.db .
  ```
- Фото товаров лежат в `data/uploads/` — копируйте каталог целиком:
  `rsync -az mikan:/opt/mikan/deploy/data/uploads/ ./uploads-backup/`

## Восстановление из копии

```bash
ssh mikan
cd /opt/mikan/deploy
docker compose stop api
cp data/mikan.db data/mikan.db.before-restore           # на всякий случай
cp data/backups/mikan-2026-10-15.db data/mikan.db
rm -f data/mikan.db-wal data/mikan.db-shm                # журналы WAL от старой базы
chown 1000:1000 data/mikan.db
docker compose start api
```

## Оплата по QR-коду (СБП, Точка Банк)

Клиент платит по QR-коду на экране телефона администратора («Касса → Оформить → По QR → Показать QR-код»).
Продажа проводится сама, как только банк подтвердит оплату; в смене и отчётах сумма видна как «QR-код».

1. В интернет-банке Точки подключите приём оплаты по QR-коду через СБП (регистрация ТСП). Нужна ТСП,
   которая принимает **динамические** QR-коды.
2. «Сервисы → Интеграции и API → Создать JWT-ключ» с правами на СБП (чтение и создание QR-кодов, данные клиента).
3. Узнайте идентификаторы ТСП и счёта — скрипту нужен только ключ (на Mac из папки `server`, ключ не попадёт в историю):
   ```bash
   read -rs "TOCHKA_JWT?Ключ Точки: " && echo && TOCHKA_JWT="$TOCHKA_JWT" npx tsx src/scripts/tochka-setup.ts
   ```
   или на сервере: `docker compose exec api node dist/scripts/tochka-setup.js` (если ключ уже в `.env`).
   Скрипт напечатает готовые строки `TOCHKA_MERCHANT_ID=...` и `TOCHKA_ACCOUNT_ID=...`.
4. Пропишите в `/opt/mikan/deploy/.env` три строки — `TOCHKA_JWT=...`, `TOCHKA_MERCHANT_ID=...`, `TOCHKA_ACCOUNT_ID=...`
   (`ssh mikan 'nano /opt/mikan/deploy/.env'`) и перезапустите: `docker compose up -d`.
   В логе запуска должно быть `"qrPayments":"tochka"`.
5. Проверьте: в приложении в «Оплате» появилась строка «QR-код».

Важно:
- QR-код действует 10 минут. Если клиент оплатил уже после отмены, продажа не проводится (деньги могли взять
  иначе) — в рабочий чат Telegram придёт сообщение, как и при любой оплате, которую не удалось провести.
- Возврат денег по QR делается в интернет-банке Точки (возврат по СБП); в приложении — обычный «Возврат» чека.
- Сертификат API Точки выдан российским удостоверяющим центром (Минцифры). Корневой сертификат
  `server/certs/russian-trusted-root-ca.pem` (SHA-256 `D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31`,
  действует до 2032 г.) используется только для запросов к Точке, остальные соединения сервера ему не доверяют.
- Чеки по 54-ФЗ Точка за оплату по QR не формирует — их по-прежнему выбивает касса студии.

## Смена домена

1. Направьте DNS-запись (A) нового домена на IP сервера.
2. В `/opt/mikan/deploy/.env` поменяйте `DOMAIN=` и `PUBLIC_URL=`.
3. `ssh mikan 'cd /opt/mikan/deploy && docker compose up -d'` — Caddy сам выпустит сертификат.
4. В iOS-приложении укажите новый адрес сервера.

По умолчанию используется `95-170-124-192.sslip.io` (sslip.io резолвит имя в IP, сертификат выдаётся Let's Encrypt).

## Полезное

- Бот работает только при `BOT_ENABLED=true` в `.env` и включённом боте в настройках приложения.
  Если Telegram недоступен, API продолжает работать, а бот переподключается сам (см. логи `api`).
- ИИ: при пустом `AI_API_KEY`, выключенном ИИ в настройках или исчерпанном лимите (`AI_DAILY_LIMIT`,
  `AI_CHAT_HOURLY_LIMIT`) бот вежливо отвечает, что администратор скоро ответит, и помечает чат.
- Часы сервера могут быть в другом поясе — это не важно: контейнер работает в UTC, а «сегодня»,
  отчёты, памятки и напоминания считаются по часовому поясу студии из настроек.
