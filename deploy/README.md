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

## Импорт прайс-листа услуг

Скрипт заводит услуги из прайс-листа (`server/src/scripts/price-list.ts`) с картинками-обложками
(`server/assets/service-images`, лежат в образе) и, с `--link-history`, разбирает историю записей из YCLIENTS
на строки услуг. Запускать после деплоя:

```bash
ssh mikan
cd /opt/mikan/deploy
# 1. Копия базы на всякий случай
docker compose exec -T api node -e "new (require('better-sqlite3'))('/app/data/mikan.db').backup('/app/data/mikan-before-services.db').then(() => console.log('ok'))"
# 2. Пробный прогон: ничего не пишет, печатает JSON-сводку
docker compose exec -T api node dist/scripts/import-services.js --link-history
# 3. Применить
docker compose exec -T api node dist/scripts/import-services.js --apply --link-history
```

- Уже существующие услуги (например, «До 5СМ», «Мочка») находятся по названию и синонимам и не дублируются;
  у них заполняются только пустые поля. `--update-existing` перезаписывает название, группу, цены, описание,
  варианты, порядок и описание картинки по прайсу (длительность, активность, фото работ и уже загруженная
  обложка сохраняются).
- Картинки копируются в `data/uploads/`; `--images=<каталог>` — взять их из другого места.
- `--link-history`: записи без услуг получают строки из названия записи («LOBE Мочка + ROOK Руук» → «Мочка» +
  «Рук»), цена записи делится между строками пропорционально прайсу. Название записи не меняется (в приложении
  оно показывается как «Описание»). Связываются только записи, где хотя бы одна часть названия есть в прайсе;
  остальные части такой записи становятся строками без услуги каталога («ТАТУ + Хеликс» → «Тату» + «Хеликс»).
  Записи, где ни одна часть не распознана («Коррекция бровей», свободное описание), не трогаются — их число
  в `history.skippedUnmapped`.
- Перед `--apply` посмотрите в пробном прогоне `history.sampleLinked` (примеры: название → строки) и
  `history.unmapped` (нераспознанные части названий).
- Повторный запуск безопасен: услуги не дублируются, записи со строками пропускаются, а повторный импорт записей
  из YCLIENTS (`import-appointments.js`) по-прежнему узнаёт уже загруженные визиты по названию.

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
