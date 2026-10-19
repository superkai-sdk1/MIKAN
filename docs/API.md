# MIKAN STUDIO — API contract (v1)

This document is the single source of truth shared by the server (`server/`) and the iOS app (`ios/`).
If the implementation must deviate, update this file in the same change.

## Conventions

- Base URL: `https://<host>/api` (production default host: `95-170-124-192.sslip.io`; local dev: `http://localhost:3000/api`).
- Auth: every endpoint except `POST /api/auth/login` and `GET /api/health` requires `Authorization: Bearer <token>`.
  A token of a deactivated employee is rejected with `401`.
- JSON, `camelCase` keys. Omitted optional fields and `null` mean the same thing on input; the server always outputs every field (using `null`).
- IDs: integers. Telegram chat IDs: integers (int64, fit in a JS double).
- Instants: ISO 8601 UTC strings with milliseconds, e.g. `"2026-10-15T11:00:00.000Z"`.
- Calendar dates (birthday, report days): `"YYYY-MM-DD"`.
- Money: **integer rubles** (no kopecks) everywhere.
- Phones are normalized by the server: Russian numbers (`8XXXXXXXXXX`, `7XXXXXXXXXX`, `+7 (XXX) XXX-XX-XX`, `9XXXXXXXXX`) → `+7XXXXXXXXXX`; anything else → `+` followed by digits.
- Lists: `{ "items": [...] }`. Paginated lists (`?limit=&offset=`, default limit 50, max 200) add `"total"`.
- Errors: non-2xx with body
  ```json
  { "error": { "code": "validation_error", "message": "Текст для пользователя на русском" } }
  ```
  Codes: `unauthorized` (401), `forbidden` (403), `not_found` (404), `validation_error` (400),
  `conflict` (409), `insufficient_stock` (409), `schedule_conflict` (409), `rate_limited` (429),
  `payment_provider_error` (502, the bank did not answer), `upstream_error` (502, an external service such as AI
  image generation failed), `internal` (500).
  `message` is always human-readable Russian; the app shows it as is.
- Roles: every employee has a `role` (`owner` | `admin` | `master`, see «Roles»); a request beyond it → `403 forbidden`
  with a Russian message («Это доступно владельцу студии», «Можно менять только свои записи»).
- Idempotency: `POST /sales`, `POST /sales/:id/refund`, `POST /receipts`, `POST /cash/operations`,
  `POST /products/:id/movements`, `POST /products/:id/movements/batch`, `POST /products/:id/purchases`
  and the prepayment writes `POST /appointments/:id/deposit`, `…/deposit/refund`, `…/deposit/retain` accept an optional `Idempotency-Key: <UUID>` header. The app generates one key per user action and resends the
  same key when it retries that action (timeout, dropped connection, repeated tap after an unclear outcome).
  - The first request with a key runs normally; its successful response is stored for **24 h**, scoped to the
    employee (key + endpoint + employee + response).
  - A repeat with the same key, endpoint and body (key order and key case do not matter) does **not** run again:
    the server returns the stored response with `200` and the header `Idempotent-Replayed: true`.
  - The same key with a different body or endpoint → `409 conflict`
    («Повторный запрос отличается от исходного. Обновите экран и попробуйте снова.»).
  - Errors are not stored: a failed request changed nothing, so retrying it with the same key runs it again.
  - A malformed key → `400 validation_error`. Without the header the endpoints behave as before (no deduplication).

## Entities

### Employee
```json
{ "id": 1, "name": "Анна", "login": "anna", "phone": "+79991234567", "color": "#FF7A1A",
  "isMaster": true, "role": "master", "active": true, "createdAt": "..." }
```
`color` — hex used for the master's appointments in the calendar. `isMaster` — performs procedures (shows in master pickers).
`role` — what the employee may do (see «Roles»); independent of `isMaster` (an owner may also be a master).

### Roles
Three roles; the server checks every request (the app only hides what a role can't use).
- `owner` — everything. The only role that manages employees (create, edit others, roles, deactivate), pay rules,
  payroll of others and adjustments, and reads the audit log.
- `admin` — everything except what is owner-only above.
- `master` — sees the whole calendar and all clients; creates, edits, moves and cancels **only their own
  appointments** (`masterId` = themselves: creating for another master, editing another master's appointment or
  giving theirs to another master → `403` «Можно менять только свои записи»), and the prepayment operations of their
  own appointments. Completes **any** appointment (`POST /appointments/:id/complete` — completing a visit is a till
  action, e.g. at checkout, so the aftercare memo goes out). Full POS and cash register (receipts, sales, refunds,
  shifts, cash operations, QR), the dashboard, clients (read, create, edit, Telegram link), bot chats (read, reply,
  mark read, `needsAttention`), scheduled messages and booking requests, their own staff code. Reads the catalog,
  products, stock and settings but does not change them; no reports or analytics.

| Area | owner | admin | master |
|---|---|---|---|
| Employees: list | ✓ | ✓ | ✓ |
| Employees: create, edit others, role, active | ✓ | — | — |
| Own profile: name, phone, color, password (`PATCH /employees/:me`) | ✓ | ✓ | ✓ |
| Appointments (create, edit, move, cancel) & prepayments | ✓ | ✓ | own only |
| Completing a visit (`POST /appointments/:id/complete`, e.g. at checkout) | ✓ | ✓ | ✓ |
| POS, sales, refunds, cash, QR, dashboard | ✓ | ✓ | ✓ |
| Clients, history | ✓ | ✓ | ✓ |
| Services, products, categories, aftercare templates, stock movements, purchases, revisions, image generation: write | ✓ | ✓ | — |
| Reports and analytics (`/reports/*`) | ✓ | ✓ | — |
| Settings (studio, bot), knowledge base, staff chat binding (`PUT/DELETE /bot/chats/:chatId/employee`), `POST /bot/test`: write | ✓ | ✓ | — |
| Work schedules: read | ✓ | ✓ | ✓ |
| Work schedules: change | ✓ | ✓ | — |
| Payroll: own statement and own pay rules (read) | ✓ | ✓ | ✓ |
| Payroll: others, pay rules (write), adjustments | ✓ | — | — |
| Audit log | ✓ | — | — |

Everything not listed (reads of catalog, settings, uploads, QR config, …) is open to every role. Rules:
- At least one active `owner` must remain: demoting or deactivating the last one → `400` «В студии должен остаться
  хотя бы один владелец». Nobody changes their own `role` or deactivates themselves.
- The role is read from the database on every request: a change applies at once, no new login needed.
- Bot staff mode follows the role: the `analytics` tool answers a master «Отчёты доступны владельцу и
  администратору»; the other staff tools are read-only and open to all.
- Existing staff after the update: the first account (created at install) is `owner`, masters are `master`, the rest
  `admin`; the owner adjusts roles in the app. A new employee defaults to `master` when `isMaster`, else `admin`.

### WorkSchedule (графики мастеров)
```json
{ "employeeId": 3,
  "weekly": [ { "start": "11:00", "end": "20:00", "breaks": [ { "start": "14:00", "end": "14:30" } ] },
              null, { "start": "12:00", "end": "21:00", "breaks": [] }, null, null, null, null ],
  "days": [ { "date": "2026-10-23", "off": true, "start": null, "end": null, "breaks": [], "note": "Отпуск" } ] }
```
- `weekly` — 7 entries Monday…Sunday: `null` = day off, else working hours `"HH:MM"` in the studio timezone (`end`
  later than `start`, `"24:00"` = midnight) with `breaks` inside them (non-overlapping). `weekly: null` = no own
  schedule: the employee works the studio hours (`workdayStart`–`workdayEnd`) every day — today's behaviour.
- `days` — exceptions for single dates (vacation, sick day, other hours): `off: true`, or own `start`/`end`/`breaks`.
  An exception wins over `weekly`. `GET` returns exceptions from today on (past ones with `?from=`).
- **Working time** of a date = its exception, else its `weekly` entry, else the studio hours; minus breaks.
- Effects:
  - The bot offers and accepts only the master's working time (free slots, `reschedule_appointment`); a master off
    that day is not offered.
  - Creating or moving an appointment (app) outside the master's working time — a day off, outside the hours, into a
    break — → `409 schedule_conflict` «Фатима не работает 23 октября» / «Фатима работает 21 октября с 12:00 до 21:00» /
    «У Фатимы перерыв 14:00–14:30» unless `force: true` (same flag as the overlap check). A name the server cannot
    decline safely (several words, «-ь», Latin) reads «Анна Иванова: перерыв 14:00–14:30». A move = a new `startsAt` /
    `endsAt` or another `masterId`; status changes and edits that keep the time are not checked. Only dates with an
    own schedule (`source` `weekly` or `day`) are checked: the studio hours never restrict.
  - The app's calendar shades each master's non-working time and marks masters off for the day.
  - The morning staff digest lists who works today with hours («👥 Сегодня работают: Амина 11:00–20:00, Фатима
    12:00–21:00»; masters without an own schedule with the studio hours; «Сегодня никто из мастеров не работает» when
    all are off), when any master has an own schedule for today.

### PayRules (правила зарплаты)
```json
{ "salaryMonthly": 0, "perDay": 1500,
  "servicePercent": 40, "categoryPercent": { "tattoo": 50, "piercing": null, "other": null },
  "productPercent": 10, "deductMaterials": true }
```
All optional numbers default to 0 / `null`; percents 0…100, money ≥ 0 (integer rubles).
- `salaryMonthly` — fixed pay per month, counted per day: each day of the period earns `salaryMonthly / days in that
  month` (a whole month earns exactly `salaryMonthly`).
- `perDay` — for each studio day on which the employee completed at least one visit (as master) or made a sale.
- `servicePercent` — share of the **service revenue of their completed visits** (their `masterId`): the service lines
  of the non-refunded sales of those visits, after the sale discount (split proportionally like analytics).
  `categoryPercent` overrides it per service category (`null` = use `servicePercent`).
- `deductMaterials` — the cost of consumables written off for the visit (usage movements × the product's unit cost)
  is subtracted from that visit's service revenue before the percent (never below 0).
- `productPercent` — share of the goods and jewelry revenue they sold: product lines of non-refunded sales, attributed
  to the visit's master when the sale belongs to an appointment, else to the employee who made the sale.
- Rules are versioned by `effectiveFrom` (studio date): each visit, sale and day is counted by the version in force
  that day. Days before the first version earn nothing.

### PayrollStatement (расчётный лист)
```json
{ "employee": { EmployeeRef }, "from": "2026-10-01", "to": "2026-10-31",
  "services": { "visits": 42, "revenue": 210000, "materials": 6300, "amount": 81480 },
  "products": { "revenue": 35000, "amount": 3500 },
  "salary": 0, "days": 18, "perDay": 27000,
  "adjustments": { "bonus": 5000, "penalty": 0, "advance": 20000, "payout": 0 },
  "earned": 116980, "paid": 20000, "due": 96980 }
```
`from`/`to` — studio-local dates, inclusive. `earned` = services + products + salary + perDay + bonus − penalty;
`paid` = advance + payout; `due` = earned − paid. Rounded to whole rubles per line.
The detailed statement adds `"lines"`: `[ { "date", "kind": "service"|"product", "appointmentId", "saleId",
"name", "category", "revenue", "materials", "percent", "amount" } ]` (date ascending) and `"adjustmentItems"`:
`[PayrollAdjustment]` (date ascending).
- A visit counts on its own date (studio date of `startsAt`) with its non-refunded sales, whenever they were paid; a
  product line counts on the day of its sale. `services.visits` — completed visits as master (a refunded one still
  counts, earning nothing); `days` — days worked: a completed visit, or a sale made (refunded later or not).
- Line `materials` — the visit's materials split across its service lines by revenue; `category` — the service
  category (`tattoo` | `piercing` | `other` for custom lines), `null` for products; `percent` — `0` on days before the
  first rules version (the line is shown, earning nothing). Service lines of sales without an appointment earn no
  service percent (no master).

### PayrollAdjustment
```json
{ "id": 1, "employee": { EmployeeRef }, "date": "2026-10-15", "kind": "advance", "amount": 20000,
  "note": "Аванс", "cashOperationId": 31, "createdBy": { EmployeeRef }, "createdAt": "..." }
```
`kind`: `bonus` (премия) | `penalty` (штраф) | `advance` (аванс) | `payout` (выплата); `amount` > 0.

### AuditEntry (журнал действий)
```json
{ "id": 1, "at": "...", "employee": { EmployeeRef } | null, "source": "app",
  "action": "appointment.update", "entity": "appointment", "entityId": 1846,
  "summary": "Запись №1846 (Анна Иванова) перенесена с 20 октября, 14:00 на 21 октября, 15:00",
  "changes": { "startsAt": { "from": "...", "to": "..." } } }
```
`source`: `app` | `bot_staff` | `bot` (a client through the bot) | `online` (a client on the booking page or in the
Mini App) | `system` (the server by itself: automatic prepayment retain, a QR payment confirmed by the bank, an unpaid
online hold released). `employee` is `null` for `bot` and `system`.
`changes` — `{ field: { from, to } }` of what changed (`null` when not applicable); passwords and tokens never appear.

### EmployeeRef / ClientRef / ServiceRef (embedded summaries)
```json
{ "id": 2, "name": "Анна", "color": "#FF7A1A" }                         // EmployeeRef
{ "id": 1, "name": "Иван", "lastName": "Петров", "phone": "+79991234567", "telegramLinked": true } // ClientRef
{ "id": 3, "name": "Прокол мочки", "category": "piercing" }             // ServiceRef
```
`ClientRef.lastName` may be `null`; apps show the client's full name (see Client) wherever they name a client.

### Client
```json
{ "id": 1, "name": "Иван", "lastName": "Петров", "phone": "+79991234567", "instagram": "ivan.p",
  "telegramNick": "ivan_petrov", "birthday": "1995-04-12", "notes": "Аллергия на никель", "source": "instagram",
  "telegramLinked": true, "telegramUsername": "ivanp", "botEnabled": true,
  "archived": false, "createdAt": "...", "updatedAt": "...",
  "stats": null }
```
- The client card: `name` (first name, required), `lastName`, `birthday`, `phone` (required), `telegramNick`; the
  other fields are optional extras.
- Full name = `name` + `" "` + `lastName` (blank parts skipped): apps show it in lists, appointments, checkout and
  history; the bot and staff notifications use it too. Cards created before last names existed may hold the whole
  name in `name` with `lastName: null`.
- `phone` is required for new clients. It may be `null` only for older cards (e.g. imported from YCLIENTS); such
  cards are read and edited as usual.
- `telegramNick` — the Telegram username typed by staff, without `@` (Latin letters, digits and `_`, 4–32 chars;
  `@nick` and `t.me/nick` are accepted on input). `telegramUsername` is read-only: the username of the linked bot
  chat. Apps show `telegramNick`, falling back to `telegramUsername`.
- `source`: free text; app offers `instagram`, `telegram`, `рекомендация`, `с улицы`, `другое`.
- `botEnabled`: whether the bot may send this client aftercare and reminders.
- `stats` is `null` in lists and filled in `GET /clients/:id`:
  `{ "visits": 3, "totalSpent": 25000, "lastVisitAt": "..." | null, "upcomingAppointments": 1 }`
  (`visits` = completed appointments; `totalSpent` = sum of non-refunded sales totals).

### Service
```json
{ "id": 1, "name": "Соски", "category": "piercing", "group": "Тело",
  "price": 2500, "priceMax": null, "priceFrom": false, "durationMin": 45,
  "description": "Nipple. Прокол проходит через сосок, избегая ареолы",
  "imageUrl": "/uploads/5d2e….jpg", "imagePrompt": "a tasteful front view of a male chest with …",
  "photos": ["/uploads/3f1c….jpg", "/uploads/9a0b….jpg"],
  "variants": [ { "name": "Один", "price": 2500, "durationMin": null },
                { "name": "Два", "price": 4000, "durationMin": 60 } ],
  "depositAmount": 0,
  "aftercareTemplateId": 2, "freshProcedure": true, "healingCheckDays": 7, "jewelryChangeWeeks": 6,
  "jewelryIds": [1, 7], "consumables": [ { "productId": 12, "quantity": 1 }, { "productId": 15, "quantity": 2 } ],
  "active": true, "sort": 0 }
```
- `jewelryIds` — catalog jewelry compatible with the service (the same link as `Product.serviceIds`, edited from either
  side); the bot offers these pieces when a client asks what fits the procedure. `[]` when none.
- `consumables` — the consumption norm of one procedure: consumables (`kind: consumable`) and how many units it
  uses. Completing an appointment deducts the norms of its services (see `complete`); `presence` consumables are
  listed with `quantity: 1` and are never deducted. `[]` when none.
- `freshProcedure` — the service leaves a fresh wound: «Свежий прокол» (piercing), «Свежее тату» (tattoo), «Нужна
  памятка по уходу» (other). Aftercare memos are sent only for appointments with at least one such service (see
  `complete`); a jewelry change, cleaning or consultation keeps it `false`. On create it defaults to whether
  `aftercareTemplateId` is set (older builds do not send it); PATCH without it keeps the value.
- `healingCheckDays` (1…60 or `null`) — the bot asks the client «Как заживает?» that many days after the visit (see
  «Follow-ups» in the Bot section). Migrated services with `freshProcedure` get `7`, others `null`.
- `jewelryChangeWeeks` (1…52 or `null`) — the bot suggests booking a jewelry change (a shorter bar once the swelling is
  gone) that many weeks after the visit. `null` = never (the default).
- `depositAmount`: prepayment required to book this service (whole rubles); `0` — no prepayment. An appointment's
  `depositRequired` defaults to the sum over its lines' catalog services (a service booked twice counts twice).
- `category`: `tattoo` | `piercing` | `other` (drives the default aftercare template and icons).
- `group`: the service's catalog category inside `category` («Лицо», «Ухо», «Тело», «Доп. услуги», …) or `null` —
  a `CatalogCategory` of section `service` (see below); lists are grouped by category, then group in the categories'
  order.
- Price: `price` — base / minimal price (the default amount of a booked line); `priceMax` — optional upper bound;
  `priceFrom` — the final price is set per appointment. The server stores `priceFrom = true` whenever `priceMax`
  is set; `priceMax` must be greater than `price`. Display:
  - `priceMax` set: `price > 0` → «от 2 000 до 5 000 ₽», `price = 0` → «до 10 000 ₽»;
  - otherwise `priceFrom` → «от 15 000 ₽», `price = 0` → «Бесплатно», else «2 500 ₽».
- `imageUrl`: the schematic cover picture (upload path) shown in the catalog, POS and the service card, and sent by
  the bot when it consults a client about this service; `null` when none. Cover shown by apps = `imageUrl` ??
  `photos[0]` ?? category icon.
- `imagePrompt`: what the cover picture shows (subject text used to generate it; any language), or `null` —
  then generation uses the service name, category and description.
- `photos`: up to 12 upload paths (`/uploads/…`, from `POST /uploads`) — photos of real works; `[]` when none.
- `variants`: up to 20 priced options (`name` 1–100 chars, `price`, optional `durationMin` overriding the service
  duration); `[]` when none. Booking a service with variants books one variant: the line name is
  `"<service name> — <variant name>"` and its price/duration come from the variant.

### AftercareTemplate
```json
{ "id": 1, "name": "Уход за татуировкой", "category": "tattoo",
  "steps": [ { "dayOffset": 0, "text": "..." }, { "dayOffset": 1, "text": "..." }, { "dayOffset": 7, "text": "..." } ],
  "createdAt": "...", "updatedAt": "..." }
```
`dayOffset: 0` is sent a few minutes after the appointment is completed; `dayOffset: N > 0` is sent N days later at
`botSettings.aftercareHour` (studio local time).

### CatalogCategory
```json
{ "id": 4, "section": "jewelry", "serviceCategory": null, "name": "Лабрет", "position": 0, "itemCount": 12 }
```
The warehouse has four sections: `jewelry` (Украшения), `service` (Услуги), `consumable` (Расходники) and `goods`
(Товары). Each section has its own categories in staff order (`position`, 0-based); service categories exist per
service `category` (`serviceCategory`: `tattoo` | `piercing` | `other`; `null` for product sections).
- Items link to a category by name: `Product.category` (in the section of its `kind`) and `Service.group` (in its
  `category`). Saving an item with a category name matching an existing one (case- and «ё»-insensitive) stores that
  category's spelling; a new name creates the category at the end. Older builds keep sending plain names.
- `itemCount` — products / services (inactive included) in the category.
- Apps group products and services by category in the categories' order; items without a category come last
  («Без категории»). (`GET /products` / `GET /services` keep their own sort order.)

### Product (jewelry, goods and consumables)
```json
{ "id": 1, "kind": "jewelry", "name": "Лабрет", "sku": "LB-12", "category": "Лабрет",
  "material": "Титан ASTM F136", "threadType": "internal", "thicknessMm": 1.2,
  "color": "Серебристый", "stone": "Фианит", "supplier": "Industrial Strength",
  "description": "...", "price": 1500, "cost": 600, "unit": "шт",
  "photos": ["/uploads/3f1c….jpg", "/uploads/9a0b….jpg"], "photoUrl": "/uploads/3f1c….jpg",
  "serviceIds": [3, 7], "stockMode": "quantity", "presenceStatus": null, "active": true, "archived": false,
  "variants": [
    { "id": 1, "name": "6 мм", "sku": null, "price": null, "cost": null,
      "quantity": 4, "minQuantity": 1, "lowStock": false },
    { "id": 5, "name": "8 мм", "sku": "LB-12-08", "price": 1700, "cost": 700,
      "quantity": 0, "minQuantity": 1, "lowStock": true } ],
  "quantity": 4, "minQuantity": 2, "lowStock": true, "size": "6 мм, 8 мм",
  "createdAt": "...", "updatedAt": "..." }
```
- `kind`: `jewelry` (sold to clients, visible to the bot) | `goods` (other things sold at the POS: aftercare sprays,
  gift cards…; sizes allowed, listed by the bot as «Товары») | `consumable` (used in procedures, not sold).
- `stockMode` (consumables only, else always `quantity`): `quantity` — counted in units like everything else;
  `presence` — only «есть / заканчивается / нет» is tracked (`presenceStatus`: `ok` | `low` | `out`, `null` in
  `quantity` mode). Presence consumables take no quantity movements (`400`); staff mark the status in the card or during
  a stock count, and record each restock with what it cost (`POST /products/:id/purchases`), so the analytics counts
  their expense. `lowStock` of a presence consumable = `presenceStatus != "ok"`.
- `archived` — deleted by staff but kept for its history (`DELETE /products/:id`): never listed, only fetched by id.
- `variants` — the sizes of the product (always at least one), in the order staff arranged them. Stock lives on
  variants: every receipt, sale, write-off, usage, count and return moves one variant.
  - A product without sizes has a single variant with `name: ""`. With two or more variants every `name` is required
    and unique within the product (case-insensitive). Consumables always have exactly one variant.
  - `sku`, `price`, `cost` — the size's own values; `null` = the product's. Selling price of a size =
    `variant.price ?? product.price`, cost = `variant.cost ?? product.cost`, article = `variant.sku ?? product.sku`.
  - `quantity` is maintained only through stock movements; `lowStock` (derived): `quantity <= minQuantity`.
  - Sizes removed in the editor disappear from `variants`; one with stock history is kept on the server (archived),
    so movements and sales still name it.
- Product-level `quantity` (Σ variants), `minQuantity` (Σ variants), `lowStock` (at least one variant is low) and
  `size` (variant names joined with `", "`, `null` when no variant has a name) are derived, output only, and keep
  older app builds working. Apps read `variants`.
- Jewelry attributes (all optional, `null` when not set):
  - `material` — free text; apps offer «Титан ASTM F136», «Титан ASTM F1295», «Хирургическая сталь 316L»,
    «Сталь ASTM F138», «Золото 585», «Золото 750», «Ниобий», «Биопласт (PTFE)», «Стекло».
  - `threadType`: `internal` (внутренняя резьба) | `external` (внешняя) | `threadless` (безрезьбовое, push-pin).
  - `thicknessMm` — bar / wire thickness in millimetres (`0 < x ≤ 30`, up to two decimals). Apps add the gauge:
    0.8 = 20G, 1.0 = 18G, 1.2 = 16G, 1.6 = 14G, 2.0 = 12G, 2.5 = 10G, 3.2 = 8G, 4.0 = 6G, 5.0 = 4G, 6.0 = 2G, 8.0 = 0G.
  - `color` (metal / anodizing colour), `stone` (insert: «Фианит», «Опал», …), `supplier` — free text up to 100 chars.
  - `serviceIds` — catalog services (piercing zones) the jewelry suits, e.g. «Хеликс», «Септум»; `[]` when none.
    The bot names them when it lists the jewelry.
- `photos`: up to 10 upload paths (`/uploads/…`), the first is the cover; `photoUrl` (derived) = `photos[0]` ?? `null`
  — shown in the POS catalog, the stock list and sent by the bot. Paths are relative to the server origin.
- Apps show markup = `price − cost` (and its share of `cost` in %), per size when the size has its own price or cost.

### StockMovement
```json
{ "id": 1, "productId": 1, "productName": "Лабрет", "variantId": 5, "variantName": "8 мм",
  "delta": -1, "quantityAfter": 11,
  "type": "sale", "note": null, "saleId": 5, "appointmentId": null, "revisionId": null, "amount": null,
  "employee": { "id": 1, "name": "Анна", "color": "#FF7A1A" }, "createdAt": "..." }
```
`type`: `receipt` (приход) | `sale` | `return` | `writeoff` (списание) | `usage` (расход на процедуру) | `adjustment` (инвентаризация)
| `purchase` (покупка расходника «есть / нет»: `delta` 0, `quantityAfter` 0, `amount` — what it cost).
`amount` — rubles paid: on `purchase`, and on a `receipt` recorded with `unitCost` (`unitCost × quantity`); `null`
otherwise.
`variantName` — the size's current name (`""` for a product without sizes); `quantityAfter` — the stock of that size
after the movement. `revisionId` — the stock count (`StockRevision`) an `adjustment` came from, else `null`.

### StockRevision (ревизия)
```json
{ "id": 3, "number": 3, "section": "consumable", "note": "Конец месяца",
  "employee": { EmployeeRef }, "counted": 24, "changed": 3,
  "surplus": 2, "shortage": 5, "surplusCost": 80, "shortageCost": 1200,
  "presenceChanges": [ { "productId": 15, "productName": "Антисептик", "from": "ok", "to": "low" } ],
  "movements": [ StockMovement ], "createdAt": "..." }
```
One stock count: what was counted and what differed. `counted` — sizes counted plus presence consumables marked;
`changed` — of them, those that differed; `surplus` / `shortage` — units found above / below the expected stock
(`…Cost` — the same at `variant.cost ?? product.cost`, unknown costs count as 0). `movements` — its `adjustment`
movements (only in `GET /stock/revisions/:id` and the `POST` response; `[]` in lists). `section` — the section counted
or `null` for a mixed count.

### Appointment
```json
{ "id": 1, "client": { ClientRef }, "master": { EmployeeRef }, "service": { ServiceRef } | null,
  "services": [ { "id": 10, "serviceId": 3, "name": "Соски — Два", "category": "piercing",
                  "price": 4000, "durationMin": 60 },
                { "id": 11, "serviceId": null, "name": "Подбор украшения", "category": null,
                  "price": 0, "durationMin": null } ],
  "title": "Тату на предплечье, эскиз согласован", "startsAt": "...", "endsAt": "...",
  "status": "scheduled", "price": 8000, "notes": "...",
  "deposit": 2000, "depositRequired": 2000, "depositStatus": "paid",
  "depositOperations": [ DepositOperation ], "depositLink": QrPayment | null,
  "saleId": null, "receiptId": null, "completedAt": null, "createdAt": "...", "updatedAt": "...",
  "cancellation": { "freeUntil": "...", "lateRetain": 2000, "noShowRetain": 2000 },
  "channel": "web", "onlineState": "awaiting_confirmation", "holdUntil": null }
```
`channel` — where it was booked: `app` (staff) | `bot` (the AI in Telegram) | `miniapp` (the Telegram Mini App) |
`web` (the booking page). `onlineState` — an online booking not settled yet: `awaiting_payment` (the time is held until
`holdUntil` while the client pays the prepayment by QR) | `awaiting_confirmation` (staff confirm or reject it) | `null`
(settled, or made by staff). Its `status` stays `scheduled` and it occupies its time like any appointment (see
«Online booking»).
`cancellation` — what the studio's rules (`StudioSettings.cancellation`) mean for this appointment while it has a
prepayment (held, else required); `null` when neither. `freeUntil` — the last moment a free cancellation is possible
(`null` when `freeHours` is 0); `lateRetain` / `noShowRetain` — rubles kept after a later cancellation / a no-show,
from the held prepayment (or the required one while nothing is held yet). They are counted from what is held now, so
after a partial retain they describe the remainder.
`status`: `scheduled` | `confirmed` | `completed` | `cancelled` | `no_show`. `saleId` — the sale that paid for it.
`receiptId` — its open receipt in the POS (`OpenReceipt`, the visit has started), `null` when none.
Visits carried over from YCLIENTS were paid in cash at the studio: the server maintenance script
`pay-imported-appointments --before=<the day MIKAN started>` (dry run by default; `--apply`) records each unpaid
scheduled / confirmed / completed visit that started before that day as a completed cash sale dated at the end of the
visit (note «Перенесено из YCLIENTS», no cash shift) — one item per booked service line, or one item at the visit
price — and completes the visit. Cancelled visits and no-shows are left as they are.
- Prepayment (see «Prepayments» below):
  - `depositRequired` — prepayment the studio asks for (defaults to the services' `depositAmount`; editable).
  - `deposit` — prepayment **held** for this appointment right now: received − applied in sales + returned by sale
    refunds − refunded to the client − retained. (Older builds read it as «prepayment received».)
  - `depositStatus`: `none` (nothing required or nothing to wait for) | `waiting` (required, nothing received yet,
    appointment `scheduled`/`confirmed`) | `paid` (`deposit > 0`; may be less than required) | `applied` (counted in a
    sale) | `refunded` (returned to the client) | `retained` (kept by the studio after a cancellation / no-show).
    Precedence: `paid` → `applied` → `retained` → `refunded` → `waiting`/`none`.
  - `depositOperations` — the prepayment ledger of this appointment, oldest first (`[]` when none).
  - `depositLink` — the latest SBP QR code issued for this appointment's prepayment (any status), or `null`.
- `services` — the booked service lines in order (`[]` when none). `name`/`price`/`durationMin` are snapshots taken
  at booking; `serviceId` is `null` for a custom line or a deleted catalog service; `category` comes from the
  linked catalog service (`null` otherwise).
- `service` — legacy single-service field kept for older app builds: the catalog service of the first line that
  has one (`null` otherwise).
- `title` — free-form description (sketch, zone, jewelry). Apps show service names first and fall back to `title`.
- `price` — the appointment total; equals the sum of line prices unless set explicitly.

### Sale
```json
{ "id": 1, "number": 17, "client": { ClientRef } | null, "employee": { EmployeeRef },
  "appointmentId": null, "shiftId": 3,
  "items": [ { "id": 1, "type": "product", "productId": 1, "variantId": 5, "variantName": "8 мм",
               "serviceId": null, "name": "Лабрет — 8 мм", "quantity": 1, "price": 1500, "total": 1500 } ],
  "subtotal": 1500, "discount": 0, "total": 1500,
  "payments": { "cash": 1500, "card": 0, "transfer": 0, "qr": 0, "deposit": 0 },
  "status": "completed", "note": null, "refundedAt": null, "refundReason": null, "createdAt": "..." }
```
- `type`: `product` (requires `productId`; decrements the stock of the sold size) | `service` (`serviceId` optional;
  `name` required when no `serviceId`).
- Product items: `variantId` — the size sold; `variantName` — its name at the moment of sale (`null` for services,
  for a product without sizes and for items sold before sizes existed); `name` = `"<product> — <size>"` (just the
  product name without a size), so receipts and history always show the size.
- `number`: sequential human-readable receipt number.
- `status`: `completed` | `refunded`.
- `payments.qr` — paid by an SBP QR code (Tochka); only set on sales created from a confirmed `QrPayment`.
- `payments.deposit` — part of the total covered by the appointment's prepayment (money received earlier and
  already counted when received, so it is not cash in the drawer now). `cash + card + transfer + qr + deposit = total`.

### OpenReceipt (открытый чек)
```json
{ "id": 7, "appointment": Appointment | null, "client": { ClientRef } | null,
  "items": [ { "type": "product", "productId": 1, "variantId": 5, "variantName": "8 мм", "productKind": "jewelry",
               "serviceId": null, "name": "Лабрет — 8 мм", "quantity": 1, "price": 1500, "total": 1500, "stock": 3 },
             { "type": "service", "productId": null, "variantId": null, "variantName": null, "productKind": null,
               "serviceId": 3, "name": "Прокол мочки", "quantity": 1, "price": 2500, "total": 2500, "stock": null } ],
  "subtotal": 4000, "discount": 0, "total": 4000, "itemCount": 2, "note": null,
  "openedBy": { EmployeeRef }, "createdAt": "...", "updatedAt": "..." }
```
- A receipt being put together before payment. Nothing is sold yet: no stock moves, a prepayment stays held. Several
  receipts can be open at once (one per visit in progress plus receipts without an appointment), and every device sees
  the same list. An appointment has at most one open receipt.
- `items` — the lines in order, as the app saved them. Product lines: `name` = `"<product> — <size>"` from the current
  catalog (the saved name when the product is gone), `variantName` — the size's name (`null` without sizes),
  `productKind` — `jewelry` | `goods`, `stock` — the size's current quantity (`null` when the size is gone).
  Service lines: `name` as saved, `productKind`/`stock` `null`. `price` — the unit price saved for the line.
- `subtotal = Σ quantity × price`, `total = subtotal − discount`, `itemCount = Σ quantity`.
- `appointment` — the whole appointment it pays for (status, held prepayment), `null` without one.
- `openedBy` — the employee who opened it.

### DepositOperation (prepayment ledger entry)
```json
{ "id": 7, "appointmentId": 4, "type": "receive", "amount": 2000, "method": "transfer",
  "saleId": null, "shiftId": 3, "qrPaymentId": null, "note": null,
  "employee": { EmployeeRef } | null, "createdAt": "..." }
```
- `type`: `receive` (money taken from the client) | `apply` (counted in sale `saleId`) | `unapply` (sale `saleId` was
  refunded: its prepayment part is held for the appointment again) | `refund` (returned to the client) |
  `retain` (kept by the studio after a cancellation / no-show).
- `method`: `cash` | `card` | `transfer` | `qr` for `receive` and `refund`; `null` otherwise.
- `shiftId`: the cash shift open at that moment (`null` when none). A `cash` receive / refund always has one.
- `qrPaymentId`: the SBP QR code a `receive` came from. `employee`: who recorded it (`null` for migrated entries;
  for a QR receive — who issued the code). `note`: comment / reason.

### QrPayment
```json
{ "id": 5, "kind": "sale", "appointmentId": null, "status": "pending", "amount": 3000,
  "payload": "https://qr.nspk.ru/AD10001B38T99KA99CD8S37FMTH8CFQ7?type=02&bank=100000000065&sum=300000&cur=RUB&crc=43B6",
  "expiresAt": "...", "sentAt": null, "error": null, "sale": null, "createdAt": "..." }
```
- `kind`: `sale` (QR part of a checkout; the server sells the cart when paid) | `deposit` (an appointment's
  prepayment; when paid the server records a `receive` with `method: "qr"`, no sale). `appointmentId` — the
  appointment of a `deposit` code (`null` for `sale`).
- `sentAt` — when the bot last sent this code's link to the client in Telegram (`deposit` only), else `null`.
- `payload` — the link to encode into the QR image (opens the client's bank app).
- `status`: `pending` → `paid` | `expired`; `pending` → `cancelled` (→ `paid` without `sale` if the client pays it anyway).
- `sale` — the `Sale` the server created once the bank confirmed the payment; `null` until then.
- `error` — while `pending`: a declined attempt (the client may retry the same code) or «bank unreachable, still
  checking»; when `paid` without `sale`: why the cart was not sold (paid after cancel, stock ran out, appointment already
  paid…) — staff finish the sale by hand (the app moves the QR share to «Перевод») or refund in the bank. Such payments
  are also sent to the staff Telegram chat.

### CashShift
```json
{ "id": 3, "openedAt": "...", "openedBy": { EmployeeRef }, "openingCash": 5000,
  "closedAt": null, "closedBy": null, "closingCash": null, "note": null,
  "expectedCash": 8500, "difference": null,
  "summary": { "salesCount": 3, "revenue": 10000, "cash": 2500, "card": 5000, "transfer": 0, "qr": 0, "deposit": 2500,
               "refunds": 0, "cashRefunds": 0, "cashIn": 0, "cashOut": 0,
               "deposits": { "received": 3000, "cash": 1000, "card": 0, "transfer": 2000, "qr": 0,
                             "refunded": 0, "cashRefunded": 0, "retained": 0 } },
  "operations": [ CashOperation ] }
```
- Sales part: `revenue` = totals of the shift's sales = `cash + card + transfer + qr + deposit` (`deposit` — the part
  covered by prepayments received earlier).
- `deposits` — prepayment operations recorded while the shift was open: `received` (all methods) with its split by
  method, `refunded` (all methods) and `cashRefunded`, `retained`.
- `expectedCash = openingCash + summary.cash − summary.cashRefunds + summary.deposits.cash − summary.deposits.cashRefunded
  + summary.cashIn − summary.cashOut` (computed live while open; frozen at close).
- `difference = closingCash − expectedCash` after close.
- `operations` is included in `GET /cash/shift/current` and `GET /cash/shifts/:id`, empty array in lists.
- At most one shift is open at a time. Sales attach to the open shift if there is one (a shift is not required to sell).

### CashOperation
```json
{ "id": 1, "shiftId": 3, "type": "out", "amount": 1000, "reason": "Инкассация",
  "employee": { EmployeeRef }, "createdAt": "..." }
```
`type`: `in` (внесение) | `out` (изъятие). Requires an open shift.

### BotChat
```json
{ "chatId": 123456789, "client": { ClientRef } | null, "employee": { EmployeeRef } | null,
  "telegramName": "Иван", "username": "ivanp",
  "aiPaused": false, "needsAttention": false, "unreadCount": 2,
  "lastMessage": { BotMessage } | null, "updatedAt": "..." }
```
- `needsAttention` — the bot handed the conversation to staff (cleared when staff replies or marks read).
- `employee` — the studio employee recognised in this chat by the phone number they shared with the bot, or bound to
  it by staff in the app (`PUT /bot/chats/:chatId/employee`; see «Staff chats» in the Bot section): the bot answers
  this chat in staff mode. Only an **active** employee is shown — a deactivated one is `null` and loses staff mode at
  once (it comes back if the employee is reactivated, until staff unlink it). `null` for client chats. Apps mark such
  chats «Сотрудник: Анна»; `DELETE /bot/chats/:chatId/employee` unlinks (`204`).

### BotMessage
```json
{ "id": 1, "chatId": 123456789, "role": "user", "text": "Сколько стоит прокол хеликса?",
  "employee": { EmployeeRef } | null, "createdAt": "..." }
```
`role`: `user` (client) | `assistant` (AI) | `staff` (sent from the app by an employee) | `system` (automatic: aftercare, reminders).

### ScheduledMessage
```json
{ "id": 1, "chatId": 123456789, "client": { ClientRef }, "appointmentId": 4,
  "kind": "aftercare", "sendAt": "...", "text": "...",
  "status": "pending", "sentAt": null, "error": null }
```
`kind`: `aftercare` | `reminder` | `healing_check` | `jewelry_change` | `reschedule_notice`. `status`: `pending` | `sent` | `failed` | `cancelled`.
An appointment has one `reminder` per `BotSettings.reminderOffsets` entry whose moment is still in the future. A
reminder sent on the day of the visit is headed «⏰ Сегодня ждём вас…», an earlier one «🗓 Напоминаем о записи…»; both
carry the inline buttons «✅ Приду» and «🔁 Перенести» (see «Reminder buttons» in the Bot section).

### BookingRequest (created by the bot)
```json
{ "id": 1, "chatId": 123456789, "client": { ClientRef } | null, "contactName": "Иван",
  "phone": "+79991234567", "serviceName": "Прокол хеликса", "preferredTime": "в субботу после 15:00",
  "comment": "...", "status": "new", "createdAt": "...", "updatedAt": "..." }
```
`status`: `new` | `processed` | `rejected`.

### KnowledgeEntry (bot knowledge base)
```json
{ "id": 1, "title": "Противопоказания", "content": "...", "active": true, "sort": 0, "updatedAt": "..." }
```

### StudioSettings
```json
{ "name": "MIKAN STUDIO", "address": "", "phone": "", "workingHours": "Ежедневно 11:00–21:00",
  "instagram": "", "website": "", "about": "", "timezone": "Europe/Moscow",
  "workdayStart": "10:00", "workdayEnd": "21:00",
  "cancellation": { "freeHours": 24, "lateRetainPercent": 100, "noShowRetainPercent": 100, "autoRetain": false },
  "reviewLinks": { "yandex": "https://yandex.ru/maps/org/…", "twogis": "", "google": "" },
  "onlineBooking": { "enabled": true, "leadMinutes": 120, "horizonDays": 60, "holdMinutes": 15, "stepMinutes": 30,
                     "note": "" } }
```
- `onlineBooking` — the client-facing booking (bot, Mini App, booking page; see «Online booking»): `enabled` (default
  `true`; `false` → the booking page says «Онлайн-запись временно недоступна» and the bot falls back to booking
  requests); `leadMinutes` (0…2880, default 120) — the earliest start from now; `horizonDays` (1…180, default 60) — how
  far ahead; `holdMinutes` (5…60, default 15) — time to pay the prepayment; `stepMinutes` (15 | 30 | 60, default 30) —
  the grid of offered starts from the beginning of the master's working day; `note` (≤ 500) — shown to clients on the
  booking page («Возьмите с собой паспорт»). On PUT omitted = unchanged.
- `cancellation` — the studio's prepayment rules, told to clients and applied when a visit that holds a prepayment is
  cancelled or missed:
  - `freeHours` (0…336) — a cancellation at least this many hours before the start is free (the whole prepayment can
    be refunded); `0` = never free. `lateRetainPercent` / `noShowRetainPercent` (0…100) — the share of the held
    prepayment the studio keeps after a later cancellation / a no-show. Defaults 24 / 100 / 100.
  - `autoRetain` (default `false`) — when the appointment becomes `cancelled` late or `no_show`, the server itself
    records the `retain` of that share (reason «Поздняя отмена — меньше 24 ч до записи» / «Неявка»); any remainder
    stays held for staff to refund. With `false` nothing happens by itself and the app proposes the amount.
  - On PUT omitted = unchanged (older builds never send it); each field is validated, an invalid one → `400`.
- `reviewLinks` — where clients leave a review (`https://…`, ≤ 500 characters each; `""` = none): the bot offers them
  after a healing check-in. On PUT omitted = unchanged.
- `workdayStart` / `workdayEnd` — working hours «с» / «до», `"HH:MM"` in the studio `timezone` (`"24:00"` = midnight;
  the end must be later than the start). The app's calendar (day / 3 days / week) starts and ends at these hours.
  They are **not** a booking limit: staff may book or move appointments to any time, the server accepts them, and
  the calendar widens its range to show appointments outside the hours. Defaults `11:00`–`21:00`; settings saved
  before these fields existed take them from the first `HH:MM–HH:MM` range in `workingHours`.
- `workingHours` — free text for clients (the bot quotes it); when empty, the bot names `workdayStart`–`workdayEnd`.

### BotSettings
```json
{ "enabled": true, "aiEnabled": true, "greeting": "...", "extraInstructions": "",
  "aftercareHour": 12, "remindersEnabled": true, "reminderOffsets": [1440, 120], "reminderHoursBefore": 24,
  "morningDigestAt": "09:30", "eveningDigestAt": "21:30",
  "botUsername": "mikan_studio_bot", "staffChatBound": false, "aiConfigured": true }
```
- `morningDigestAt` / `eveningDigestAt` — when the bot sends the morning summary («что на сегодня») and the evening
  summary («итоги дня») to every staff chat, `"HH:MM"` in the studio timezone; `null` = that summary is off. Defaults
  `"09:30"` and `"21:30"`. On PUT: omitted = unchanged, `null` = off (older builds never send them). See «Staff digests».
- `botUsername`, `staffChatBound`, `aiConfigured` are read-only (ignored on PUT).
- `reminderOffsets` — when the bot reminds clients of an appointment: minutes before its start, e.g. `[1440, 120]` =
  «за 1 день» and «за 2 часа». 1–6 distinct integers, each 15…20160 (15 minutes … 14 days); the server returns them
  sorted descending (earliest reminder first). Default `[1440]`. Invalid lists → `400` («Напоминания»: …).
- `reminderHoursBefore` — kept for older builds: output = the first (largest) offset in whole hours, within 1…168. On
  PUT it is used only when `reminderOffsets` is absent and its value differs from the current output (older builds
  resend what they read), and then means a single reminder that many hours before (1–168). Settings saved before
  `reminderOffsets` existed read as `[reminderHoursBefore × 60]`.
- Changing `reminderOffsets` or `remindersEnabled` rebuilds the pending reminders of every upcoming scheduled /
  confirmed appointment (moments already in the past are skipped; reminders already sent stay sent).

## Endpoints

### Health & auth
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/health` | — | `{ "ok": true, "version": "1.0.0" }` |
| POST | `/auth/login` | `{ login, password }` | `{ token, employee: Employee }` · `401 unauthorized` on bad credentials · rate-limited (10/min per IP) |
| GET | `/auth/me` | — | `Employee` |

The token lives 90 days. On first start, if there are no employees, the server creates one from `ADMIN_LOGIN` / `ADMIN_PASSWORD` / `ADMIN_NAME` env.

### Badges & dashboard
| Method | Path | Response |
|---|---|---|
| GET | `/badges` | `{ "unreadChats": 2, "needsAttention": 1, "newBookingRequests": 1, "lowStock": 3, "onlineAwaiting": 2 }` (the app polls every 30 s; `lowStock` — active products with at least one low size; `onlineAwaiting` — online bookings in the future waiting for staff confirmation) |
| GET | `/dashboard` | `{ "date": "2026-10-15", "appointments": [Appointment] (today, studio tz, excl. cancelled), "revenueToday": 12000, "salesCountToday": 4, "openShift": CashShift \| null, "badges": {…same as /badges} }` |

### Employees
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/employees?includeInactive=true` | — | `{ items: [Employee] }` (active only by default) |
| POST | `/employees` | `{ name, login, password (≥6), phone?, color?, isMaster, role? }` | `Employee` · owner · `409 conflict` if login taken |
| PATCH | `/employees/:id` | any of `{ name, login, password, phone, color, isMaster, role, active }` | `Employee` · owner; anyone for themselves: `name`, `phone`, `color`, `password` only · cannot deactivate yourself or change your own role (`400`) |

- A field sent with its current value counts as unchanged (the app sends the whole card): a master saving their own
  card with the same `login`, `isMaster`, `role` and `active: true` gets `200`; a changed one → `403` «Это доступно
  владельцу студии». Changing your own role → `400` «Нельзя изменить собственную роль»; deactivating yourself →
  `400` «Нельзя отключить собственную учётную запись».

### Work schedules
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/schedules?from=&to=` (studio dates, ≤ 62 days) | — | `{ items: [ScheduleDayOut] }` — every active master × every date |
| GET | `/employees/:id/schedule?from=` | — | `WorkSchedule` |
| PUT | `/employees/:id/schedule` | `{ weekly: [7 × entry \| null] \| null }` | `WorkSchedule` · owner, admin |
| PUT | `/employees/:id/schedule/days` | `{ from, to (≤ 62 days), off, start?, end?, breaks?, note? }` | `WorkSchedule` · sets every date in range · owner, admin |
| DELETE | `/employees/:id/schedule/days?from=&to=` | — | `WorkSchedule` · removes the exceptions in range · owner, admin |

- `to` defaults to `from` (a single date) on `PUT …/days` and `DELETE …/days`; both are inclusive. `off: true` ignores
  `start` / `end` / `breaks`; `note` ≤ 200 characters. A master writing → `403` «Это доступно владельцу и
  администратору». `WorkSchedule` from writes lists the exceptions from today on.
- `GET /schedules`: `from` and `to` required; items sorted by date, then masters by name (the masters are those the
  bot books with: active `isMaster` employees, every active employee when none is).

`ScheduleDayOut`: `{ "employeeId": 3, "date": "2026-10-21", "working": true, "start": "12:00", "end": "21:00",
"breaks": [ { "start": "15:00", "end": "15:30" } ], "source": "weekly", "note": null }` — `source`: `weekly` |
`day` (an exception) | `studio` (no own schedule); `working: false` → `start`/`end` `null`. Invalid times, a break
outside the hours, overlapping breaks, `end` ≤ `start` → `400` with the Russian reason.

### Payroll
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/payroll?from=&to=` (studio dates, ≤ 400 days) | — | `{ from, to, items: [PayrollStatement] }` — owner: every employee with rules or activity in the period; others: only themselves |
| GET | `/payroll/:employeeId?from=&to=` | — | `PayrollStatement` + `lines` + `adjustmentItems` · owner or themselves |
| GET | `/employees/:id/pay-rules` | — | `{ current: PayRules \| null, history: [ { effectiveFrom, rules: PayRules, createdBy: EmployeeRef \| null, createdAt } ] }` · owner or themselves |
| PUT | `/employees/:id/pay-rules` | `{ effectiveFrom? (default today), ...PayRules }` | same as GET · owner · the same `effectiveFrom` replaces that version |
| POST | `/payroll/adjustments` | `{ employeeId, date?, kind, amount, note?, fromCash? }` | `PayrollAdjustment` · owner · `fromCash: true` (advance / payout only) also records a cash withdrawal «Аванс: Фатима» in the open shift (`409` without one) · accepts `Idempotency-Key` |
| DELETE | `/payroll/adjustments/:id` | — | `204` · owner · its cash withdrawal, if any, stays (correct it in the till) |

`from` and `to` are required (`400` «Конец периода должен быть не раньше начала», «Период — не больше 400 дней»).
The owner's list has every employee (inactive ones included) with a rules version in force by `to` or with visits,
sales, attributed products or adjustments in the period, by name. `current` of the pay rules — the version in force
today (`null` before the first one). Anyone else asking for another employee → `403` «Это доступно владельцу студии».

### Audit log
| Method | Path | Response |
|---|---|---|
| GET | `/audit?from=&to=&employeeId=&entity=&entityId=&source=&limit=&offset=` | `{ items: [AuditEntry], total }` newest first · owner |

`from` / `to` — instants (`to` exclusive); `entity` — one entity or a comma-separated list (`entity=appointment,deposit`:
an appointment with its prepayment); `limit` default 50, max 200. Anyone but the owner → `403` «Это доступно владельцу
студии».

- Logged: every successful write request from the app (`POST`/`PUT`/`PATCH`/`DELETE`) except `POST /auth/login`,
  `POST /uploads`, `POST /bot/chats/:chatId/read`, `POST /bot/staff-code`, `POST /devices`, `DELETE /devices/:token`
  and idempotent replays; online bookings and client cancellations on the booking page as `online`; client actions in
  the bot (booking request, reschedule, confirm «Приду») as `bot`; staff bot actions as `bot_staff`; automatic
  prepayment retain and bank-confirmed QR payments as `system`.
- `summary` is written for people, in Russian, impersonal (the employee's gender is not stored; the app shows who
  next to it): «Запись №1846 (Анна Иванова) перенесена с … на …», «Продажа №1580 возвращена: 3 500 ₽»,
  «Цена «Мочка»: 1 600 → 1 800 ₽», «Фатиме назначена роль «Мастер»». Entities: `appointment`, `deposit`, `sale`, `receipt`, `cash`, `client`,
  `service`, `product`, `stock`, `category`, `aftercare`, `knowledge`, `employee`, `schedule`, `payroll`,
  `settings`, `bot`. `action` is `<entity>.<verb>` (`appointment.move`, `sale.refund`, …).
- `entityId` is the id of what the entry is about: `deposit` — the appointment; `stock` — the product (`null` for a
  stock count); `cash` — the shift; `schedule` and `payroll` — the employee; `bot` — the chat id (may be negative),
  the booking request or the scheduled message; `sale` — the sale (`null` for a QR code not yet paid); `settings` and
  a category reorder — `null`. An edit that changed nothing is logged too («… сохранена без изменений»); a write
  without a specific summary gets «Изменение: PUT /…» with the entity taken from the path.
- Kept 2 years (older rows are pruned daily). A failure to write the log never fails the request (it is logged).
- The app shows the log to the owner (More → «Журнал действий», filters by employee and section) and, on an
  appointment, client, sale or product card, its own history (`?entity=&entityId=`).

### Clients
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/clients?search=&archived=false&limit=&offset=` | — | `{ items: [Client], total }` — search matches the full name (first and last name), phone digits, instagram, Telegram nick and bot username; sorted by full name |
| GET | `/clients/:id` | — | `Client` with `stats` |
| POST | `/clients` | `{ name, phone, lastName?, birthday?, telegramNick?, instagram?, notes?, source?, botEnabled? }` | `Client` · `400` without `phone` («Телефон»: обязательное поле) · `409 conflict` if phone already belongs to another client (message names that client) |
| PATCH | `/clients/:id` | any of the same fields + `archived` | `Client` · `400` when clearing a phone the client has |

- PATCH: omitted fields are kept, `null` / `""` clears an optional field. A phone, once set, can be changed but not
  removed. For a card without a phone, `phone: null` changes nothing, so older builds (which send every field, the
  empty phone as `null`) can still edit such cards.
| GET | `/clients/:id/history` | — | `{ items: [HistoryEntry], appointments: [Appointment], sales: [Sale] }` newest first (see History) |
| GET | `/clients/:id/chat` | — | `{ "chat": BotChat \| null }` — the client's Telegram bot chat (the linked chat, else the latest chat attributed to the client); `null` if the client has never written to the bot |
| POST | `/clients/:id/telegram-link` | — | `{ "url": "https://t.me/<bot>?start=c<token>" }` — opening it links the Telegram chat to this client |

### Services
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/services?includeInactive=true` | — | `{ items: [Service] }` sorted by `sort`, then name |
| POST | `/services` | `{ name, category, group?, price, priceMax?, priceFrom?, durationMin, description?, imageUrl?, imagePrompt?, photos?, variants?, depositAmount?, aftercareTemplateId?, freshProcedure?, healingCheckDays?, jewelryChangeWeeks?, jewelryIds?, consumables?, active?, sort? }` | `Service` |
| PATCH | `/services/:id` | any of the above | `Service` |
| GET | `/services/:id/history?limit=&offset=` | — | `{ items: [HistoryEntry], total }` — who got this service and when, newest first |

- `jewelryIds` (≤ 100) replaces the compatible jewelry (`kind: jewelry` products, `400` «Украшение не найдено»
  otherwise); `consumables` (≤ 50, `{ productId, quantity: 1…1000 }`, distinct products) replaces the norm (`kind:
  consumable` products, `400` «Расходник не найден» otherwise). Omitted — unchanged.
| POST | `/services/:id/image/generate` | `{ prompt? }` (≤ 1000 chars) | `Service` with a new `imageUrl` — generates the schematic cover with AI (Polza Media API, ~1–2 min; apps use a 4-minute timeout). A non-empty `prompt` is used and saved as `imagePrompt`; `prompt: ""` / `null` resets it (generates from the name/description and saves `imagePrompt = null`); without `prompt` the saved `imagePrompt` (or name/description) is used. Only `imageUrl` (and `imagePrompt` when `prompt` is sent) change, so edits made during generation are kept. `409 conflict` when the AI key (`AI_API_KEY` + `AI_BASE_URL`) is not configured or a generation for this service is already running, `502 upstream_error` when generation fails (message says why). The previous picture file is kept. |

### Aftercare templates
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/aftercare-templates` | — | `{ items: [AftercareTemplate] }` |
| POST | `/aftercare-templates` | `{ name, category, steps: [{ dayOffset ≥ 0, text }] (≥1) }` | `AftercareTemplate` |
| PATCH | `/aftercare-templates/:id` | any of the above | `AftercareTemplate` |
| DELETE | `/aftercare-templates/:id` | — | `204` (services referencing it get `aftercareTemplateId = null`) |

### Catalog categories
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/catalog/categories?section=` | — | `{ items: [CatalogCategory] }` by section, service category, position |
| POST | `/catalog/categories` | `{ section, serviceCategory?, name }` | `CatalogCategory` (added at the end) · `409` «Категория «Лабрет» уже есть» |
| PATCH | `/catalog/categories/:id` | `{ name }` | `CatalogCategory` — renames it and every item in it · `409` when another category of the same section (and service category) has that name |
| PUT | `/catalog/categories/order` | `{ ids: [4, 2, 9] }` | `{ items: [CatalogCategory] }` — positions in this order; every id of one section (and service category), all of them listed (`400` otherwise) |
| POST | `/catalog/categories/:id/merge` | `{ intoId }` | `CatalogCategory` (the target) — moves the items into `intoId` (same section and service category) and deletes this one |
| DELETE | `/catalog/categories/:id` | — | `204` — the items stay, without a category |

`serviceCategory` is required for `section: "service"` and must be absent / `null` otherwise. Names: 1–100 chars.

### Products & stock
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/products?kind=jewelry&search=&lowStock=true&includeInactive=true` | — | `{ items: [Product] }` sorted by category, name |
| GET | `/products/:id` | — | `Product` |
| POST | `/products` | see below | `Product` |
| PATCH | `/products/:id` | any of the POST fields | `Product` |
| DELETE | `/products/:id?writeOff=true` | — | `{ "deleted": true }` or `{ "archived": true, "writtenOff": 3 }` · `409` while stock is left without `writeOff` |
| POST | `/products/:id/movements` | `{ type: "receipt"\|"writeoff"\|"usage"\|"adjustment", variantId?, quantity, unitCost?, note? }` | `{ product: Product, movement: StockMovement }` · accepts `Idempotency-Key` |
| POST | `/products/:id/movements/batch` | `{ type, note?, unitCost?, lines: [{ variantId, quantity, unitCost? }] }` | `{ product: Product, movements: [StockMovement] }` · accepts `Idempotency-Key` |
| POST | `/products/:id/purchases` | `{ amount, note?, presenceStatus? }` | `{ product: Product, movement: StockMovement }` · accepts `Idempotency-Key` |
| GET | `/products/:id/movements?variantId=&limit=&offset=` | — | `{ items: [StockMovement], total }` |
| GET | `/products/:id/history?variantId=&limit=&offset=` | — | `{ items: [HistoryEntry], total }` — who bought this product (or this size) and when, newest first |
| GET | `/stock/movements?type=&limit=&offset=` | — | `{ items: [StockMovement], total }` newest first |

- `search` matches the name, SKUs (product and sizes), category, material, colour, stone, supplier and size names.
  `lowStock=true` — products with at least one low size (presence consumables: status not `ok`).
- `POST/PATCH /products` also take `stockMode` and `presenceStatus` (consumables only; `400` for other kinds).
  Switching a consumable to `presence` keeps its counted stock aside (shown nowhere) and starts `ok` when it had
  stock, `out` otherwise; switching back to `quantity` uses the counted stock again.
- `goods` follow the rules of `jewelry` for sizes, sales and stock; only consumables are limited to one size.

`POST /products` body:
```json
{ "kind": "jewelry", "name": "Лабрет", "sku": "LB-12", "category": "Лабрет",
  "material": "Титан ASTM F136", "threadType": "internal", "thicknessMm": 1.2, "color": null, "stone": null,
  "supplier": "Industrial Strength", "description": null, "price": 1500, "cost": 600, "unit": "шт",
  "photos": ["/uploads/3f1c….jpg"], "serviceIds": [3], "active": true,
  "variants": [ { "name": "6 мм", "minQuantity": 1, "initialQuantity": 4 },
                { "name": "8 мм", "sku": "LB-12-08", "price": 1700, "cost": 700, "minQuantity": 1, "initialQuantity": 0 } ] }
```
- `variants` (1–50): `{ id?, name?, sku?, price?, cost?, minQuantity?, initialQuantity? }`. A new size with
  `initialQuantity > 0` gets a `receipt` movement «Начальный остаток».
- PATCH with `variants` replaces the list (the new order is kept): an item with `id` (a size of this product) updates
  that size (`initialQuantity` is ignored), an item without `id` adds a size, and a size left out is removed — deleted
  when it has no movements or sales, archived otherwise. A size added without `id` under the name of an archived size
  of the product brings that size back (same `id`, its history kept). Removing a size that still has stock → `409 conflict`
  («Размер «8 мм»: на складе 3 шт — спишите остаток, прежде чем удалять размер»); an unknown `id` → `400`.
- Validation (`400`): a duplicate size name, an empty name when there are two or more sizes, more than one size for a
  consumable.
- Without `variants` (older builds) the legacy fields `size`, `minQuantity` and `initialQuantity` (POST only) describe
  the only size. On PATCH they change the only size; when the product has several sizes, a changed `size` or
  `minQuantity` → `409 conflict` «У «Лабрет» несколько размеров — обновите приложение MIKAN, чтобы изменить их»
  (unchanged values, which older builds always resend, are ignored).
- `photos` (≤ 10) replaces the photos; without it, `photoUrl` (older builds) replaces the cover (`null` removes it)
  and keeps the other photos.
- `serviceIds` (≤ 30) replaces the linked services; an unknown id → `400`.
- `quantity` is never set by PATCH.
- `DELETE` removes a product from the warehouse. One with no stock movements and no sold items is deleted for good
  (its sizes, links to services and consumption norms go with it): `{ "deleted": true }`. One with history is
  **archived** — hidden from every list, the POS, the bot, stock counts and the low-stock badge, but sales, history
  and movements still name it: `{ "archived": true, "writtenOff": 0 }`; its links to services and consumption norms are
  removed, and it can no longer be sold or moved (`400` «Позиция удалена со склада»). Stock left on it → `409 conflict`
  «На складе ещё 3 шт. — спишите остаток, чтобы удалить позицию» unless `?writeOff=true`, which first writes the
  stock of every size off (a presence consumable has no stock to write off: it is deleted as is) (`writeoff` movements, note «Позиция удалена со склада»; counted as a stock expense) and
  returns `writtenOff` = the units written off. Deleting twice → `404`.

Movements:
- `quantity` semantics: `receipt` — positive amount added; `writeoff`/`usage` — positive amount removed;
  `adjustment` — the **new absolute quantity** of the size after a stock count (server computes `delta`). Stock may not
  go below 0 (`409 insufficient_stock`, «Недостаточно на складе: Лабрет — 8 мм (осталось 2)»).
- `variantId` must be a current size of the product (`400` otherwise). Without it (older builds) the only size is
  used; for a product with several sizes → `409 conflict` «У «Лабрет» несколько размеров — обновите приложение MIKAN,
  чтобы провести операцию по размеру».
- `unitCost` (receipts only; ignored for other types) — what one unit cost on this delivery (0…100 000 000 ₽). The
  movement keeps `amount = unitCost × quantity`, and the cost becomes the new cost of what was received: the size's
  own `cost` when it has one, else the product's `cost` (so valuations and margins use the latest price). In `batch`
  a line's `unitCost` wins over the body's. Without `unitCost` a receipt's `amount` is `null` and costs do not change.
- `batch` records one operation for several sizes in one transaction (a delivery, a stock count of all sizes):
  1–50 lines with distinct `variantId`s. `receipt` / `writeoff` / `usage` lines need `quantity > 0`; `adjustment`
  lines whose count equals the current stock are skipped, and a count that changes nothing → `400` «Остатки не
  изменились». `movements` are in line order.
- `purchases` — a restock of a **presence** consumable (gloves, wipes…) with what it cost: `amount` 1…100 000 000 ₽
  (required), `note` (supplier, how many packs), `presenceStatus` after it (default `ok`). Writes a `purchase`
  movement (`delta` 0, `amount`) and sets the status. Other products → `400` «Сумму покупки записывают для расходников
  «есть / нет». Для остальных — приход количеством.». The analytics counts the amount as a stock expense of the day
  of the purchase (`stock.purchases`).

Stock counts (ревизии):
| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/stock/revisions` | `{ section?, note?, counts: [{ variantId, quantity }], presence: [{ productId, status }] }` | `StockRevision` · accepts `Idempotency-Key` |
| GET | `/stock/revisions?limit=&offset=` | — | `{ items: [StockRevision], total }` newest first (`movements: []`) |
| GET | `/stock/revisions/:id` | — | `StockRevision` with `movements` |

- `counts` (≤ 2 000, distinct sizes of quantity-mode products): the counted stock of each size; a differing one gets an
  `adjustment` movement «Ревизия №N» (+ note). `presence` (≤ 500, presence consumables): the marked status.
- At least one line (`400` «Ревизия пустая»); a count that matches everything is still recorded (`changed: 0`) —
  it documents that the stock was checked. One transaction; `number` is sequential.

### Uploads
| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/uploads` | `multipart/form-data`, field `file` (JPEG/PNG/HEIC/WebP, ≤ 10 MB) | `{ "url": "/uploads/<uuid>.<ext>" }` |

Files are served publicly at `GET /uploads/<name>` (outside `/api`, no auth; names are unguessable UUIDs).

### Appointments
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/appointments?from=&to=&masterId=&clientId=&status=&onlineState=` | — | `{ items: [Appointment] }` overlapping `[from, to)`, sorted by `startsAt` · `onlineState=awaiting_confirmation` (or `awaiting_payment`) lists unsettled online bookings, `from`/`to` optional with it |
| POST | `/appointments/:id/online/confirm` | — | `Appointment` · `onlineState` → `null`; the client is told («✅ Запись подтверждена…») · `409` unless `awaiting_confirmation` · a master: own only |
| POST | `/appointments/:id/online/reject` | `{ reason? }` | `Appointment` · `status` → `cancelled`, `onlineState` → `null`; the client is told, with the reason and the booking link · `409` unless `awaiting_*` · a master: own only |
| GET | `/appointments/:id` | — | `Appointment` |
| POST | `/appointments` | `{ clientId, masterId, services?, serviceId?, title?, startsAt, endsAt?, price?, depositRequired?, notes?, status?, force? }` | `Appointment` |
| PATCH | `/appointments/:id` | any of the above (incl. `status`) + `force?`, `notifyClient?` | `Appointment` |
| POST | `/appointments/:id/complete` | `{ sendAftercare: true, aftercareTemplateId?, consumables?: [{ productId, variantId?, quantity }] }` | `{ appointment: Appointment, scheduledMessages: 3, consumption: Consumption }` |
| POST | `/appointments/:id/deposit` | `{ amount > 0, method: "cash"\|"card"\|"transfer", note? }` | `Appointment` · accepts `Idempotency-Key` |
| POST | `/appointments/:id/deposit/refund` | `{ amount?, method?, reason? }` | `Appointment` · accepts `Idempotency-Key` |
| POST | `/appointments/:id/deposit/retain` | `{ amount?, reason? }` | `Appointment` · accepts `Idempotency-Key` |
| POST | `/appointments/:id/deposit/qr` | `{ delivery: "screen"\|"telegram"\|"link", amount?, chatId? }` | `DepositLinkResult` · rate limit 30/min |
| POST | `/appointments/:id/deposit/remind` | `{ chatId? }` | `DepositLinkResult` · rate limit 30/min |

- `services`: `[{ serviceId?, name?, price?, durationMin? }]` (≤ 20) — replaces all service lines (`[]` clears them).
  A line with `serviceId` defaults `name`, `price` and `durationMin` from the catalog service; a line without one
  needs `name` (`price` defaults to 0). Apps resolve variants themselves and send the variant's name/price/duration.
- Legacy `serviceId` (older builds) is used only when `services` is absent: the same service as the current first
  catalog line keeps the lines untouched (`null` included — older builds always send `null` for appointments whose
  lines are all custom); another service replaces them with that single service; `null` while the appointment has a
  catalog service clears them.
- `price` defaults to the sum of line prices (on create, and on PATCH when `services` is sent without `price`).
- `depositRequired` defaults the same way to the sum of the lines' catalog `depositAmount`. The legacy input field
  `deposit` (older builds) is ignored: prepayments change only through the prepayment endpoints below.
- Moving an appointment to `cancelled` / `no_show` / `completed` (and paying it at checkout) cancels its pending
  prepayment QR codes; a prepayment it holds stays held until staff refund or retain it (or apply it at checkout).
- `endsAt` defaults (create only) to `startsAt` + the sum of line durations; it must be after `startsAt`.
- Overlap check: if the master already has a non-cancelled, non-no-show appointment overlapping the time, respond
  `409 schedule_conflict` (message names the conflicting client and time) unless `force: true`.
- The studio's working hours (`StudioSettings.workdayStart` / `workdayEnd`) do not restrict `startsAt` / `endsAt`:
  appointments before opening or after closing are accepted. A master's own work schedule does (see
  «WorkSchedule»): outside it → `409 schedule_conflict` unless `force: true`.
- A master may create and change only their own appointments (see «Roles»); completing is open to every role.
- `notifyClient: true` on a PATCH that changes `startsAt` (a move: drag in the calendar or the edit form): when the
  client has Telegram linked and `botEnabled`, the server queues a `reschedule_notice` scheduled message sent at once
  (the sender delivers it within 30 s, with retries) with the «✅ Приду» / «🔁 Перенести» buttons:
  «Анна, ваша запись перенесена 🗓\n\nБыло: 20 октября, 14:00\nСтало: **21 октября, 15:00**\nМастер: Фатима\n\nЕсли
  новое время не подходит — нажмите «🔁 Перенести».» A pending notice of the same appointment is replaced (a move
  without the flag just drops it). Without Telegram (or without the flag) nothing is sent, nor for a move into the past
  or of an appointment that is not `scheduled` / `confirmed`; the sender skips a notice whose appointment is no longer
  active. Reminders are rescheduled as before either way.
- Consumption: `consumables` **omitted or `null`** → the server deducts the norms of the appointment's services
  (Σ over its service lines of each service's `consumables`, quantity-mode only), never failing: a consumable short of
  stock gives what it has and is reported. `consumables` given (an array, `[]` included) → exactly those, and a shortage
  is `409 insufficient_stock` (older builds always send the array). Usage is recorded once per appointment: a repeated
  `complete` writes nothing. A sale that completes a not yet completed appointment (`POST /sales` with `appointmentId`,
  also via QR) deducts the norms the same way when nothing was recorded.
  `Consumption`: `{ "used": [ { "productId": 12, "productName": "Игла 1.2", "quantity": 1 } ], "shortages": [ {
  "productId": 15, "productName": "Перчатки", "needed": 2, "deducted": 1 } ] }` (`[]`/`[]` when nothing).
- `complete`: sets `status = completed`, `completedAt = now`; writes `usage` movements for `consumables` (the only
  size of the product unless `variantId` is given; a product with several sizes needs `variantId`: `409 conflict` asking
  to update the app otherwise); when
  `sendAftercare`, the client has Telegram linked and `botEnabled`, **and at least one of the appointment's catalog
  services has `freshProcedure`**, schedules the aftercare template steps (template = `aftercareTemplateId` ?? the
  template of the first such service that has one). An appointment without a fresh procedure (only a jewelry change,
  say, or no catalog services) gets no memo whatever the app sends: `scheduledMessages: 0`. Cancels pending reminders
  of this appointment.
- Creating/rescheduling an appointment for a Telegram-linked client schedules one reminder per
  `BotSettings.reminderOffsets` entry (minutes before `startsAt`; if `remindersEnabled` and that moment is in the
  future). Cancelling / no-show / rescheduling (from the app or by the client through the bot) cancels or replaces
  pending reminders.

#### Moving an appointment in the calendar (app)
Long press on an appointment in the day / 3-day / week calendar lifts it; dragging moves it in time (snapped to 15
minutes; the duration is kept) and, in views with several days, to another day; in the day view with master columns,
to another master (owner and admin only). On release the app asks «Перенести запись Анны на 21 октября, 15:00?»
with «Уведомить клиента в Telegram» (on by default; hidden when the client has no Telegram or the new time has
already passed) and sends `PATCH` with `startsAt`, `endsAt` (and `masterId`), `notifyClient`. A `schedule_conflict`
asks «Записать всё равно?» and retries with `force: true`; cancelling or an error puts the appointment back. A master
can lift only their own appointments; completed, cancelled and no-show appointments are not draggable (nor one that
runs past midnight — it is moved in the editor).

### Prepayments (deposits)
Every prepayment movement is a `DepositOperation`; the appointment's `deposit` (held amount) and `depositStatus` are
derived from them. Money is counted once — when it is received:
- **Receive** — `POST /appointments/:id/deposit` (client paid at the studio: cash / card / transfer) or a paid
  prepayment QR code (method `qr`, recorded by the server). Allowed for `scheduled` / `confirmed` appointments only
  (`409` otherwise). Cash needs an open shift (`409 «…откройте кассовую смену»`) and counts in its
  `summary.deposits.cash` / `expectedCash`. Receiving more than `depositRequired` is allowed.
- **Apply** — at checkout the sale sends `payments.deposit` (≤ held, see Sales); the server writes an `apply`
  operation. The drawer and the payment methods of that sale count only what is paid now.
- **Sale refund** — the sale's `payments.deposit` part goes back to the appointment (`unapply`): staff then apply it
  to a new sale, refund it or retain it.
- **Refund** — `POST …/deposit/refund`: `amount` defaults to the whole held amount (≤ held), `method` to the method of
  the latest receive (`qr` = returned through the Tochka internet bank, the app only records it). Cash needs an open
  shift and is taken from the drawer (`summary.deposits.cashRefunded`). `409` when nothing is held.
- **Retain** — `POST …/deposit/retain`: the studio keeps the prepayment after a cancellation / no-show (only for
  `cancelled` / `no_show` appointments, `409` otherwise); `amount` defaults to the whole held amount.
- `reason` / `note` — free text (≤ 500), stored in the operation `note`.

**Prepayment QR codes** — `POST /appointments/:id/deposit/qr` registers a one-off SBP QR code for
`amount` (default `depositRequired − deposit`; `409 «Предоплата уже внесена»` when that is ≤ 0) and cancels the
appointment's other pending prepayment codes. Only for `scheduled` / `confirmed` appointments; `409` when QR payments
are not configured, `502 payment_provider_error` when the bank fails.
- `delivery: "screen"` — shown on the phone at the studio, valid 10 minutes (the app polls `GET /qr-payments/:id`).
- `delivery: "telegram"` — the bot sends the link to the client; `delivery: "link"` — not sent, staff share
  `payload` themselves. Both stay valid until the appointment starts (at least 30 minutes, at most 72 hours).
- Telegram delivery goes to the client's chat (the linked chat, else the latest chat attributed to the client), or to
  `chatId` (e.g. the booking request's chat — it is then attributed to the client). Before registering the code the
  server checks there is a chat and the bot is running (`409` otherwise).
- `POST …/deposit/remind` — sends the latest pending link again with a reminder text (when it has ≥ 15 minutes left),
  otherwise registers a fresh link (cancelling the old one) and sends it. `409` when nothing is left to pay.

`DepositLinkResult`:
```json
{ "appointment": Appointment, "payment": QrPayment, "sendError": null }
```
`sendError` — why the bot could not deliver the link (client blocked the bot…); the code stays valid, staff can share
`payload` another way. `payment.sentAt` is set when delivered.

When the bank confirms a prepayment code (app poll or the background check), the server records a `receive`
(`method: "qr"`, the open shift if any), sends the client a thank-you message in Telegram (when the chat is known) and
notifies the staff chat. Money is always recorded, even when it arrives on a cancelled / replaced code, for a
cancelled or already paid appointment, or above `depositRequired`: such a payment gets an `error` on the `QrPayment`
and a staff alert, and staff refund or keep the extra. Pending prepayment codes are checked at most once a minute in
the background.

### History
`HistoryEntry` — one thing done for or sold to a client:
```json
{ "id": "as10", "kind": "service", "date": "...", "name": "Соски — Два",
  "serviceId": 3, "productId": null, "variantId": null, "variantName": null,
  "quantity": 1, "price": 4000, "total": 4000,
  "client": { ClientRef } | null, "employee": { EmployeeRef } | null,
  "appointmentId": 12, "saleId": 40, "saleNumber": 17, "refunded": false }
```
- Services come from **completed** appointments: one entry per service line (`id` `as<line id>`), or one entry named
  after the appointment `title` («Процедура» when empty, `id` `at<appointment id>`, price = appointment price) when
  the appointment has no lines. `date` = `startsAt`, `employee` = master, `saleId`/`saleNumber` = the paying sale.
- Products come from sale items of type `product` (`id` `si<item id>`, `date` = sale time, `employee` = seller);
  `variantId` / `variantName` — the size sold (as in the sale item; `null` for services). `?variantId=` on
  `GET /products/:id/history` keeps one size.
  Service items of a sale count only when the sale is not linked to an appointment (otherwise the appointment
  already lists them).
- `refunded`: the sale (of the item, or the one that paid for the appointment) was refunded.
- Used by `GET /clients/:id/history` (`items`, all entries), `GET /services/:id/history` and
  `GET /products/:id/history` (paginated, default limit 50, max 200).

### Open receipts (POS)
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/receipts` | — | `{ items: [OpenReceipt] }` oldest first |
| GET | `/receipts/:id` | — | `OpenReceipt` · `404` «Чек уже оплачен или удалён» |
| POST | `/receipts` | `{ appointmentId?, clientId?, items?, discount?, note? }` | `OpenReceipt` · accepts `Idempotency-Key` |
| PUT | `/receipts/:id` | `{ appointmentId?, clientId?, items, discount?, note? }` | `OpenReceipt` |
| DELETE | `/receipts/:id` | — | `{ "ok": true }` · `404` when already gone |

- `items`: `[{ type, productId?, variantId?, serviceId?, name?, quantity, price? }]` (≤ 100) — the shape of sale items.
  Product lines need an existing sellable product (`400` for a consumable or a missing one) and one of its current
  sizes (`variantId`; omitted → its only size; several sizes → `400` «Выберите размер «Лабрет»»). Service lines need
  `name` unless `serviceId` is given. `price` defaults to the catalog price (the size's ?? the product's, the service's).
  Stock is not checked here: the sale checks it.
- `POST /receipts` with `appointmentId` — «Начать визит» (the appointment moves to the POS). If the appointment already
  has an open receipt, that receipt is returned unchanged (two devices starting one visit share it). Otherwise a new
  one: `clientId` defaults to the appointment's client; `items` omitted → the appointment's service lines (one per
  booked line when their prices add up to the appointment price, otherwise one line at the appointment price named
  like the appointment: its services, else `title`, else «Услуга»). The appointment must be unpaid and `scheduled` /
  `confirmed` / `completed`: `409` «Запись уже оплачена (чек №17)» / «Запись отменена — верните её в расписание, чтобы
  открыть чек». Without `appointmentId` — a receipt with what was sent (empty is fine).
- `PUT /receipts/:id` replaces the whole receipt (the app sends all of it; omitted `appointmentId`/`clientId`/`note`
  = none, `discount` = 0). Linking it to an appointment that has another open receipt → `409`; `0 ≤ discount ≤
  subtotal` (`400`).
- `DELETE /receipts/:id` removes the open receipt and nothing else: no stock moves, a prepayment stays held, the
  appointment keeps its status and is back among the unpaid ones (`receiptId: null`).
- Paying: `POST /sales` and `POST /qr-payments` take an optional `receiptId`. The sale deletes that receipt (if it
  still exists) in its own transaction, and also the open receipt of the sale's `appointmentId` — so sales from older
  builds and QR payments confirmed later close it too.
- Cancelling an appointment or marking it `no_show` deletes its open receipt.

### Sales (POS)
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/sales?from=&to=&clientId=&limit=&offset=` | — | `{ items: [Sale], total }` newest first |
| GET | `/sales/:id` | — | `Sale` |
| POST | `/sales` | see below | `Sale` · accepts `Idempotency-Key` |
| POST | `/sales/:id/refund` | `{ reason, restock: true }` | `Sale` (status `refunded`) · accepts `Idempotency-Key` |

`POST /sales` body:
```json
{ "clientId": 1, "appointmentId": 4,
  "items": [ { "type": "product", "productId": 1, "variantId": 5, "quantity": 1, "price": 1500 },
             { "type": "service", "serviceId": 3, "name": "Прокол мочки", "quantity": 1, "price": 2500 } ],
  "discount": 500, "payments": { "cash": 1500, "card": 0, "transfer": 0, "qr": 0, "deposit": 2000 }, "note": null,
  "receiptId": 7 }
```
- `receiptId` — the open receipt being paid (optional): deleted together with the sale (see «Open receipts»).
- `price` per item is the unit price actually charged (defaults to the catalog price if omitted: for a product, the
  size's price ?? the product's).
- Product items name the size in `variantId` (a current size of `productId`, `400` otherwise). Without `variantId`
  (older builds) the product's only size is sold; a product with several sizes → `409 conflict` «У «Лабрет» несколько
  размеров. Обновите приложение MIKAN, чтобы выбрать размер.». Consumables cannot be sold (`400`).
- `subtotal = Σ quantity × price`; `total = subtotal − discount` (`0 ≤ discount ≤ subtotal`);
  `payments.cash + payments.card + payments.transfer + payments.qr + payments.deposit` must equal `total` (`400` otherwise).
- `payments.deposit` — the appointment's held prepayment counted in this receipt: needs `appointmentId` (`400`
  otherwise) and must not exceed the held amount (`409`). The app applies `min(held, total)`; a remainder stays held
  for the appointment (staff refund or retain it). If the appointment holds a prepayment and the body has no
  `payments.deposit` key (older builds) → `409 conflict` asking to update the app, so the prepayment is not charged twice.
- `payments.qr > 0` is rejected here (`400`): a sale with a QR share is created by the server through `/qr-payments`.
- The app no longer offers card payments (cash, transfer and QR only); `payments.card` stays in the API for older
  sales and older app builds.
- Product items decrement the stock of their size (`sale` movements); quantities of one size are summed across lines
  before the check; insufficient stock → `409 insufficient_stock` ("Недостаточно на складе: Лабрет — 8 мм (осталось 0)",
  or "Лабрет (осталось 0)" for a product without sizes). Whole sale is one transaction.
- With `appointmentId`, the appointment gets `saleId` (and is marked `completed` if not already, without aftercare).
- Refund: marks `refunded`, returns product stock to the sold size (`return` movements; an archived size comes back to
  the list — unless the product now has a current size with the same name, which then gets the stock) when `restock`;
  a cash refund is attributed
  to the currently open shift (`summary.cashRefunds`). The `payments.deposit` part is not paid out: it becomes the
  appointment's held prepayment again (`unapply`).

### QR payments (SBP via Tochka Bank)
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/qr-payments/config` | — | `{ "enabled": true }` — `false` when the server has no Tochka credentials |
| POST | `/qr-payments` | same as `POST /sales`, with `payments.qr > 0` | `QrPayment` (`pending`) · `409` when not configured · `502 payment_provider_error` when the bank fails · rate limit 30/min |
| GET | `/qr-payments/:id` | — | `QrPayment` — asks the bank (at most every 2 s) and applies the answer |
| POST | `/qr-payments/:id/cancel` | — | `QrPayment` — checks the bank first, so a payment that has just arrived returns `paid` |

`GET /qr-payments/:id` and `POST /qr-payments/:id/cancel` work for prepayment codes too (`kind: "deposit"`, see
Prepayments); `POST /qr-payments` creates `sale` codes only.

Flow: the app sends the cart; the server validates it like a sale (nothing is written, stock of every size is checked),
registers a one-off SBP QR for `payments.qr` (valid 10 min) and stores the cart with its sizes and prices fixed. The app shows `payload` as
a QR and polls `GET /qr-payments/:id` every ~2 s. When the bank reports the money, the server creates the sale from the
stored cart in one transaction (with the cash/card/transfer parts as sent) and returns it in `sale`; one paid code
always yields at most one sale. A background job checks watched codes every 15 s, so a payment is recorded even if the
app was closed. An unpaid code becomes `expired` once the bank confirms it unpaid 5 minutes after `expiresAt`; while the
bank cannot be reached the code stays `pending` for up to 24 h (Tochka keeps paid codes readable that long). A cancelled
code is still watched: if the client pays it anyway, it becomes `paid` with an `error` and no sale (staff may already
have taken the money another way). Refunds of the QR part are made in the Tochka internet bank (the app only marks the
sale refunded).

### Cash register
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/cash/shift/current` | — | `{ "shift": CashShift \| null }` |
| POST | `/cash/shift/open` | `{ openingCash }` | `CashShift` · `409 conflict` if one is open |
| POST | `/cash/shift/close` | `{ closingCash, note? }` | `CashShift` (closed) |
| POST | `/cash/operations` | `{ type: "in"\|"out", amount > 0, reason }` | `CashOperation` · `409` without open shift · accepts `Idempotency-Key` |
| GET | `/cash/shifts?limit=&offset=` | — | `{ items: [CashShift], total }` newest first |
| GET | `/cash/shifts/:id` | — | `CashShift` with `operations` |

### Reports
`GET /reports/summary?from=&to=` (instants; the app sends studio-local day boundaries)
```json
{ "from": "...", "to": "...",
  "revenue": 120000, "salesCount": 40, "averageCheck": 3000, "refunds": 2500,
  "payments": { "cash": 30000, "card": 0, "transfer": 20000, "qr": 60000, "deposit": 10000 },
  "deposits": { "received": 15000, "cash": 2000, "card": 0, "transfer": 3000, "qr": 10000,
                "applied": 10000, "refunded": 1000, "retained": 2000, "held": 7000 },
  "servicesRevenue": 90000, "productsRevenue": 30000,
  "byDay": [ { "date": "2026-10-01", "revenue": 8000, "salesCount": 3 } ],
  "topProducts": [ { "productId": 1, "name": "Лабрет", "quantity": 7, "revenue": 10500,
                     "variants": [ { "variantId": 5, "name": "8 мм", "quantity": 4, "revenue": 6000 },
                                   { "variantId": 1, "name": "6 мм", "quantity": 3, "revenue": 4500 } ] } ],
  "topServices": [ { "serviceId": 3, "name": "Прокол мочки", "quantity": 12, "revenue": 30000 } ],
  "byMaster": [ { "employee": { EmployeeRef }, "appointmentsCompleted": 10, "revenue": 50000 } ],
  "newClients": 14, "appointmentsCompleted": 35, "noShows": 2 }
```
Revenue excludes refunded sales. `byDay` uses the studio timezone and lists every day in range (zeros included).
`payments` splits `revenue` by how it was paid (`deposit` — covered by prepayments received earlier).
`deposits` — prepayment operations in the period: `received` (+ by method), `applied` (counted in sales, net of
sale refunds), `refunded`, `retained` (kept after cancellations / no-shows; not part of `revenue`); `held` — the total
held for appointments at the end of the period. `held(start) + received − applied − refunded − retained = held(end)`.
`byMaster.revenue` = sales linked to that master's appointments. Item-level revenue is split proportionally to the
sale discount (rounded to whole rubles). `topProducts` are grouped by product (`name` — its current name); `variants`
splits each by size (current size name, `""` for a product without sizes), sorted like the top itself.
`/reports/summary` is kept unchanged for older app builds; current builds read `/reports/analytics`.

#### Analytics
`GET /reports/analytics?from=&to=` (instants, the app sends studio-local day boundaries) — the whole financial
picture of `[from, to)` plus the headline numbers of the **previous period of the same length**
`[from − (to − from), from)` for deltas. Same limits and `400` messages as the summary («Конец периода должен быть
позже начала», «Период отчёта — не больше 400 дней»).
```json
{ "from": "2026-10-12T21:00:00.000Z", "to": "2026-10-15T21:00:00.000Z",
  "previousFrom": "2026-10-09T21:00:00.000Z", "previousTo": "2026-10-12T21:00:00.000Z", "timezone": "Europe/Moscow",
  "totals": { "net": 10380, "gross": 11680, "refunds": 1300, "salesCount": 4, "averageCheck": 2920, "discounts": 420,
              "servicesRevenue": 2700, "productsRevenue": 8480, "cogs": 1900, "grossProfit": 2580, "marginPercent": 57.6,
              "stockExpenses": 850, "newClients": 1, "appointmentsCompleted": 1, "noShows": 1, "noShowLoss": 5000,
              "depositsReceived": 1000 },
  "previous": { …same keys as totals },
  "revenue": { "gross": 11680, "refunds": 1300, "refundsCount": 2, "net": 10380, "salesCount": 4, "averageCheck": 2920,
               "discounts": 420, "kept": 11180,
               "payments": { "cash": 6180, "card": 0, "transfer": 5500, "qr": 0, "deposit": 0 } },
  "byDay": [ { "date": "2026-10-13", "gross": 3780, "refunds": 800, "net": 2980, "salesCount": 1 } ],
  "byWeekday": [ { "weekday": 1, "revenue": 0, "salesCount": 0 } ],
  "byHour": [ { "hour": 0, "revenue": 3780, "salesCount": 1 } ],
  "services": { "quantity": 1, "revenue": 2700,
                "byCategory": [ { "category": "piercing", "quantity": 1, "revenue": 2700 } ],
                "top": [ { "serviceId": 1, "name": "Прокол хеликса", "category": "piercing", "quantity": 1, "revenue": 2700 } ] },
  "products": { "quantity": 6, "revenue": 8480, "revenueWithCost": 4480, "cogs": 1900, "grossProfit": 2580,
                "marginPercent": 57.6, "itemsWithoutCost": 2,
                "byKind": [ { "kind": "jewelry", …same margin keys } ],
                "top": [ { "productId": 1, "name": "Лабрет", "kind": "jewelry", …same margin keys,
                           "variants": [ { "variantId": 2, "name": "8 мм", …same margin keys } ] } ] },
  "stock": { "writeoffs": { "quantity": 2, "value": 800, "unitsWithoutCost": 0 },
             "usage": { "quantity": 8, "value": 50, "unitsWithoutCost": 3 },
             "purchases": { "count": 1, "value": 3500 }, "expenses": 4350,
             "top": [ { "productId": 1, "name": "Лабрет", "kind": "jewelry", "type": "writeoff", "quantity": 2, "value": 800 } ],
             "onHand": { "units": 118, "value": 6850, "unitsWithoutCost": 10,
                         "byKind": [ { "kind": "jewelry", "units": 16, "value": 5900, "unitsWithoutCost": 3 } ] } },
  "deposits": { …same as in the summary },
  "cash": { "cashIn": 500, "cashOut": 2000, "operationsCount": 2, "shiftsClosed": 1, "closingDifference": -80,
            "shortage": -80, "surplus": 0, "openingDifference": -300,
            "shifts": [ { "id": 2, "openedAt": "...", "closedAt": "...", "closedBy": { EmployeeRef },
                          "openingCash": 1200, "closingCash": 2600, "expectedCash": 2680,
                          "openingDifference": -300, "difference": -80 } ] },
  "masters": [ { "employee": { EmployeeRef }, "revenue": 3780, "salesCount": 1, "averageCheck": 3780,
                 "appointmentsCompleted": 1, "noShows": 1, "servicesCount": 2 } ],
  "clients": { "newClients": 1, "buyers": 3, "firstTime": { "count": 1, "revenue": 5000 },
               "returning": { "count": 2, "revenue": 6180 }, "anonymous": { "salesCount": 0, "revenue": 0 },
               "top": [ { "client": { ClientRef }, "revenue": 5000, "salesCount": 1, "visits": 0 } ] },
  "appointments": { "total": 4, "open": 1, "completed": 1, "cancelled": 1, "noShow": 1,
                    "noShowLoss": 5000, "cancelledValue": 2000 } }
```
Which sales count where:
- **Made** sales — created in the period, whatever their status now (a receipt refunded later was still made then).
- **Refunds** — sales refunded during the period (`refundedAt`), whenever they were made.
- **Kept** sales — the made sales that are still `completed`. Every breakdown below `revenue` (services, products,
  margins, weekdays, hours, masters, clients) counts kept sales only, so a returned receipt never inflates tops or
  margins. Item revenue is net of the sale discount, split as in the summary (`allocateDiscount`).

Fields:
- `totals` — headline numbers of the period; `previous` — the same keys for the previous period (the app shows
  deltas; a delta against `0` is shown as «—»). `servicesRevenue` / `productsRevenue` = `services.revenue` /
  `products.revenue`; `cogs`, `grossProfit`, `marginPercent` as in `products`; `stockExpenses` = `stock.expenses`;
  `newClients` as in `clients`; `appointmentsCompleted` / `noShows` / `noShowLoss` as in `appointments`;
  `depositsReceived` = `deposits.received`.
- `revenue`: `gross` — Σ totals of made sales, `salesCount` — their number, `averageCheck = round(gross / salesCount)`
  (`0` without sales), `discounts` — Σ their discounts; `refunds` / `refundsCount` — refunded in the period;
  `net = gross − refunds` («Выручка»); `kept` — Σ totals of kept sales (= `services.revenue + products.revenue`);
  `payments` — how the made sales were paid (sums to `gross`; `deposit` — covered by prepayments received earlier).
- `byDay` — every studio-local day of the range, zeros included: `gross` and `salesCount` of sales made that day,
  `refunds` made that day, `net = gross − refunds` (Σ `byDay.net` = `revenue.net`).
- `byWeekday` — always 7 entries, `weekday` 1 = Monday … 7 = Sunday; `byHour` — always 24 entries, `hour` 0–23. Both
  bucket kept sales by their studio-local time (`revenue` = Σ totals, `salesCount`).
- `services` — service items: `quantity` (Σ item quantities), `revenue`; `byCategory` by the catalog service's
  `category` (`other` for custom lines and deleted services), by revenue; `top` — up to 20 services by revenue
  (grouped by catalog service, named by its current name; custom lines grouped by name).
- `products` — product items with margin keys: `quantity`, `revenue`, `cogs` = Σ quantity × current unit cost
  (`variant.cost ?? product.cost`), `revenueWithCost` — revenue of the units whose cost is known,
  `grossProfit = revenueWithCost − cogs`, `marginPercent = grossProfit / revenueWithCost × 100` (one decimal, `null`
  when `revenueWithCost` is 0), `itemsWithoutCost` — sold units whose cost is unknown (left out of `cogs` and
  `revenueWithCost`; the app asks to fill in the cost). The same keys appear in `byKind` (one entry per product
  `kind` that sold, by revenue — any kind the server has, apps show unknown kinds by their raw name), in `top` (up to
  20 products by revenue, current names) and in each top product's `variants` (by size, current size name, `""` for a
  product without sizes; items sold before sizes existed have no size entry). Costs are today's, not the ones at sale
  time.
- `stock` — `writeoffs` and `usage` (consumables used in procedures) recorded in the period: `quantity` (units),
  `value` at the current unit cost, `unitsWithoutCost`; `purchases` — restocks of presence consumables: `count` and
  `value` (the amounts paid); `expenses = writeoffs.value + usage.value + purchases.value`; `top` — up to 20 products
  by value (`type`: `writeoff` | `usage` | `purchase`; for `purchase` `quantity` is the number of purchases). `onHand` — a snapshot **now**, not at the
  end of the period: units in stock of every product (inactive ones included), their value at cost,
  `unitsWithoutCost`, and the same split `byKind`.
- `deposits` — exactly the summary's prepayments block.
- `cash` — `cashIn` / `cashOut` / `operationsCount`: cash register operations of the period. Shifts **closed** in the
  period: `shiftsClosed`, `closingDifference` = Σ (`closingCash − expectedCash`), its negative part `shortage` (≤ 0)
  and positive part `surplus` (≥ 0); `openingDifference` = Σ (`openingCash` − `closingCash` of the shift before).
  `shifts` — those shifts with any discrepancy, newest first (≤ 20): `openingDifference` is `null` for the very first
  shift.
- `masters` — masters with completed appointments or no-shows in the period, or with kept sales linked to their
  appointments: `revenue` / `salesCount` / `averageCheck` of those sales, `appointmentsCompleted`, `noShows`,
  `servicesCount` (service lines of completed appointments; an appointment without lines counts once). Sorted by
  revenue, then completed appointments.
- `clients` — `newClients`: cards created in the period; `buyers`: clients with kept sales; `firstTime` / `returning`
  split them (`count`, `revenue`) — returning means a completed sale or a completed appointment before `from`
  (history imported from another CRM counts); `anonymous` — kept sales without a client; `top` — up to 10 clients by
  revenue with their `salesCount` and `visits` (completed appointments in the period). Apps open the client card from it.
- `appointments` — appointments **starting** in the period: `total`, `open` (`scheduled` + `confirmed`),
  `completed`, `cancelled`, `noShow`; `noShowLoss` = Σ `price` of no-shows, `cancelledValue` = Σ `price` of cancelled.

### Online booking (все каналы записи)
Clients book any active service themselves, through every channel: the AI in Telegram (`book_appointment`), the
Telegram Mini App and the booking page (`PUBLIC_URL/book`, the link for Instagram, Yandex Maps and 2GIS). All channels
use one engine and the rules below.

**What a client books.** 1–5 items `{ serviceId, variant? }` (active catalog services; `variant` — a variant `name`),
a master or «any», a start. Duration = Σ durations (variant's, else the service's; 60 min when none), `price` = Σ
prices (variant's, else `price`), `depositRequired` = Σ `depositAmount`. The appointment gets the service lines like
`POST /appointments` with `services`.

**Free time.** Starts on the `onlineBooking.stepMinutes` grid from the beginning of the master's working day (own
schedule minus breaks, else studio hours — see «WorkSchedule»), at least `leadMinutes` from now, at most `horizonDays`
ahead, the whole duration inside working time and not overlapping the master's non-cancelled, non-no-show
appointments (online holds included). The bot's `free_slots` follows the same settings. «Any master» = every active
master (`isMaster`); a booking for «any» goes to a free master at that start — the one with the fewest appointments
that day, then the lowest id.

**The client.** By phone (normalized): the existing client card, else a new one (`name`, `phone`). In the bot and the
Mini App the chat's linked client is used (the phone was shared at start); a Mini App chat without one sends name and
phone like the page, and the chat is linked to that card. At most 2 unsettled online bookings per client: a third →
`409` «У вас уже есть записи, которые ждут подтверждения — дождитесь ответа студии».

**Settlement.**
- `depositRequired > 0` and QR payments configured → `onlineState: awaiting_payment`, `holdUntil = now +
  holdMinutes`, and a prepayment QR code (`QrPayment` `kind: deposit`, amount `depositRequired`, valid until
  `holdUntil`). Paid (the usual bank confirmation) → `onlineState: null`: confirmed. Not paid by `holdUntil` (the bank
  confirms unpaid) → `status: cancelled`, notes «Предоплата не внесена вовремя», the code cancelled, the time free; the
  client is told when there is a chat.
- Otherwise (no prepayment, or QR payments not configured) → `onlineState: awaiting_confirmation`: the time is held
  until staff confirm (`…/online/confirm`) or reject (`…/online/reject`) it in the app.
- Staff are told in the staff chat (and by push): «🆕 Онлайн-запись (сайт): Анна, +7…, Мочка — 21 октября, 15:00,
  мастер Фатима · ждёт подтверждения» / «· ждёт оплату до 14:35» / «💳 Онлайн-запись оплачена: …».
- The client with a Telegram chat gets: on booking — «Заявка принята, время за вами 🙌 Подтвердим в ближайшее время»
  or the payment request with the link button «💳 Оплатить предоплату»; on confirmation or payment — «✅ Запись
  подтверждена: 21 октября, 15:00, мастер Фатима, адрес…» with the cancellation rule line; on rejection — the reason and
  the booking link. Reminders are scheduled as for any appointment.
- Background: unpaid holds are checked every minute.
- Audit: the booking is logged with source `bot` / `online`, its release with `system`.

**Booking page and Mini App** (`PUBLIC_URL/book`, static files served by the server; `/book/*` paths return the page).
One mobile-first page in Russian: service (categories → groups → services with photo, price text, duration, variants)
→ master or «Любой мастер» → a day strip and free starts → name, phone, comment → confirm. With a prepayment it shows
the QR / bank link, a countdown to `holdUntil` and waits for the payment; otherwise «Ждёт подтверждения». Then the
booking page `/book/b/<token>`: status, details, «Добавить в календарь» (`.ics`), «Получать уведомления в Telegram»
(`https://t.me/<bot>?start=b_<token>`), «Отменить запись». `?service=<id>&master=<id>` preselects. Inside Telegram
(opened from the bot's menu button «📅 Записаться» or `https://t.me/<bot>/book`) it uses the Telegram theme, the
MainButton, skips name and phone for a linked chat and sends the Mini App init data; the bot confirms in the chat.
Link previews (Open Graph): «Запись в MIKAN STUDIO».

| Method | Path (no auth) | Body | Response |
|---|---|---|---|
| GET | `/public/booking/config` | — | `{ enabled, studio: { name, address, phone, workingHours, timezone }, note, leadMinutes, horizonDays, stepMinutes, cancellationText, botUsername }` |
| GET | `/public/booking/services` | — | `{ items: [PublicService] }` active services in catalog order |
| GET | `/public/booking/masters` | — | `{ items: [ { id, name, color } ] }` active masters |
| GET | `/public/booking/days?from=&to=&items=&masterId=` | — | `{ items: [ { date, available } ] }` ≤ 31 dates; `items` = `serviceId[:variant]` comma-separated (variant URL-encoded) |
| GET | `/public/booking/slots?date=&items=&masterId=` | — | `{ date, durationMin, items: [ { startsAt, masterIds: [3, 5] } ] }` |
| GET | `/public/booking/me` | header `X-Telegram-Init-Data` | `{ linked: true, name: "Анна", phone: "+7 *** ***-**-01" }` · `401` for invalid init data |
| POST | `/public/booking` | `{ items, masterId?, startsAt, name, phone, comment?, website? }` (+ `X-Telegram-Init-Data` in the Mini App) | `PublicBooking` · `409 schedule_conflict` «Это время только что заняли — выберите другое» · `400` · `429` (5 per hour per IP) |
| GET | `/public/booking/b/:token` | — | `PublicBooking` (a pending payment is checked with the bank, at most every 2 s) |
| POST | `/public/booking/b/:token/cancel` | — | `PublicBooking` · until the start; staff are told («❌ Клиент отменил онлайн-запись №…»), a held prepayment stays for staff to refund or keep by the rules |
| GET | `/public/booking/b/:token/calendar.ics` | — | `text/calendar` event |

- `PublicService`: `{ id, name, category, group, description, priceText: "от 3 000 ₽", price, durationMin,
  depositAmount, imageUrl, variants: [ { name, priceText, price, durationMin } ] }` — no internal fields.
- `PublicBooking`: `{ token, status: "awaiting_payment"|"awaiting_confirmation"|"confirmed"|"cancelled"|"completed",
  number, items: [ { name, price } ], master: { name }, startsAt, endsAt, price, depositRequired, holdUntil,
  payment: { payload, amount, expiresAt } | null, studio: { name, address, phone }, telegramLink, calendarUrl }`.
- `website` is a honeypot: when filled the server answers as if booked and stores nothing. Phone validation as for
  clients; `name` 1…100. Unknown or inactive services, a master who is not an active master, a start that is not free
  → `400` / `409` with Russian reasons. `enabled: false` → `403` «Онлайн-запись временно недоступна».
- Mini App init data is checked as Telegram documents (HMAC-SHA256 with the key `HMAC("WebAppData", bot token)`,
  `auth_date` within 24 h); the Telegram user id is the chat id.
- `/start b_<token>` in the bot links the chat to the booking's client (when the chat has no client yet) and answers
  with the booking status; later notices of that booking go to Telegram.
- The bot sets its menu button to the Mini App («📅 Записаться», `web_app` → `PUBLIC_URL/book`) at start.

### Push notifications
Staff iPhones get push notifications through APNs (token auth). Configured by env `APNS_KEY_ID`, `APNS_TEAM_ID`,
`APNS_PRIVATE_KEY` (the `.p8` file content, base64) and `APNS_BUNDLE_ID`; without them nothing is sent (a partial set is
logged once at start).

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/devices` | `{ token, environment: "production"\|"sandbox" }` | `204` — registers the device for the current employee (a token registered by someone else moves to them) |
| DELETE | `/devices/:token` | — | `204` — on sign-out |

Events (sent next to the staff chat message about the same thing; a failed push never fails anything):
| Event | Who | Title · body | `data` |
|---|---|---|---|
| `online_booking` | owner, admin, the booked master | «Новая онлайн-запись» · «Анна · Мочка · 21 окт, 15:00 · ждёт подтверждения» | `{ type, appointmentId }` |
| `deposit_paid` | owner, admin, the appointment's master | «Предоплата получена» · «Анна · 2 000 ₽ · запись 21 окт, 15:00» | `{ type, appointmentId }` |
| `client_message` | everyone | «Клиент ждёт ответа» · «Анна: …» (a chat got `needsAttention`) | `{ type, chatId }` |
| `booking_request` | owner, admin | «Новая заявка» · «Анна · Мочка · в субботу после 15:00» | `{ type, bookingRequestId }` |
| `client_cancelled` | owner, admin, the master | «Клиент отменил запись» · «Анна · 21 окт, 15:00» | `{ type, appointmentId }` |
Devices of inactive employees get nothing. A device answered `410` / `BadDeviceToken` / `Unregistered` is deleted.
The app asks for permission after sign-in, registers the token (`POST /devices`), removes it on sign-out, and a tap
opens the appointment, the chat or the list of online bookings.

### Bot (Telegram + AI)
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/bot/chats` | — | `{ items: [BotChat] }` sorted by `updatedAt` desc |
| GET | `/bot/chats/:chatId/messages?beforeId=&limit=50` | — | `{ items: [BotMessage] }` ascending by time (the page *before* `beforeId`) |
| POST | `/bot/chats/:chatId/messages` | `{ text }` | `BotMessage` (role `staff`, delivered to Telegram immediately; clears `needsAttention`) |
| POST | `/bot/chats/:chatId/read` | — | `204` (unreadCount → 0, needsAttention → false) |
| PATCH | `/bot/chats/:chatId` | `{ aiPaused }` | `BotChat` |
| PUT | `/bot/chats/:chatId/employee` | `{ "employeeId": 3 }` | `BotChat` with `employee` — binds the chat to that active employee by hand (see Staff chats): the bot sends the staff greeting with the staff keyboard, the staff chat is notified; the chat is bound even if Telegram fails · `404` for an unknown chat · `400` for an unknown or deactivated employee |
| DELETE | `/bot/chats/:chatId/employee` | — | `204` — unlinks the employee: the staff chat becomes an ordinary client chat (`employee: null`; the employee may share the phone again) · `404` for an unknown chat |
| GET | `/bot/scheduled?status=pending` | — | `{ items: [ScheduledMessage] }` sorted by `sendAt` |
| POST | `/bot/scheduled/:id/cancel` | — | `ScheduledMessage` |
| POST | `/bot/staff-code` | — | `{ "code": "482913", "expiresAt": "...", "instruction": "Добавьте бота в рабочий чат и отправьте: /staff 482913" }` |
| POST | `/bot/test` | `{ text }` | `{ "reply": "..." }` — runs the AI with the current knowledge base as an anonymous client, nothing is sent to Telegram |
| GET | `/booking-requests?status=new` | — | `{ items: [BookingRequest] }` newest first |
| PATCH | `/booking-requests/:id` | `{ status }` | `BookingRequest` |
| GET | `/knowledge` | — | `{ items: [KnowledgeEntry] }` |
| POST | `/knowledge` | `{ title, content, active?, sort? }` | `KnowledgeEntry` |
| PATCH | `/knowledge/:id` | any of the above | `KnowledgeEntry` |
| DELETE | `/knowledge/:id` | — | `204` |

Jewelry in the bot: the AI context lists active jewelry that has at least one size in stock, with its category,
material, thread, thickness, colour, stone, suitable services, price (per size when sizes differ in price) and the
names of the sizes in stock — never quantities. `show_products` sends the cover photo with the name, material,
thickness, price and the sizes in stock (jewelry and goods in stock).

#### Client conversation (AI tools)
The AI answers clients warmly and briefly in Russian, only from the studio data (studio info, price list, jewelry in
stock, aftercare memos, knowledge base) and tool results — it never invents prices, availability, free time or
discounts. It consults on every service of the price list (procedure, duration, price and variants, prepayment,
preparation, contraindications, healing, aftercare); when the data has no answer, on medical red flags, complaints or a
request for a human it calls `handoff_to_staff`: the chat gets `needsAttention`, the staff chat is notified, and staff
answer from the app (`POST /bot/chats/:chatId/messages`). Client tools:
- `book_appointment { items: [ { serviceId, variant? } ], masterId?, startsAt, comment? }` — books online for the
  chat's linked client through the engine (see «Online booking», channel `bot`): `startsAt` is studio-local «YYYY-MM-DD
  HH:MM». The model calls it only after the client agreed to the services, the master (or «any») and the time it
  offered from `free_slots`; the result says what happens next (payment link sent as a button, or waiting for
  confirmation) and the model tells the client in plain words. Unidentified chats are asked to share the phone.
- `create_booking_request { contactName, phone, serviceName, preferredTime, comment? }` — a `BookingRequest`; staff
  confirm the time. Used when the client has no exact time in mind or online booking is off.
- `handoff_to_staff { reason }`.
- `show_service { serviceId }` — the service picture with price and variants after the reply (once per conversation).
- `show_products { productIds ≤ 5 }` — photos of pieces in stock.
- `show_jewelry_for_service { serviceId }` — a jewelry carousel of the pieces compatible with the service (see
  Catalogs). The model maps misspelled zones («Феликс» → Хеликс) onto the price list.
- `find_jewelry { query }` — searches active jewelry and goods (name, SKU, category, material, colour, stone, size
  names, thickness, thread, suitable services, description; Russian word forms tolerated), up to 8 matches: sizes in
  stock with prices or «нет в наличии» — never quantities.
- `my_appointments {}` — the upcoming scheduled / confirmed appointments of the client card **linked** to this chat
  (deep link or shared phone; a chat merely attributed to a client, e.g. an old account after re-linking, gets
  nothing): number, time, services, master, status. Unidentified chats are asked to share the phone.
- `free_slots { date, appointmentId?, serviceId?, masterId? }` — free starts on a studio-local date: inside the
  master's working time (see «WorkSchedule»: their own schedule minus breaks, else `StudioSettings.workdayStart`–
  `workdayEnd`; studio timezone), every 30 minutes from the start of their working day, at least 1 hour from now, at most 90
  days ahead, not overlapping the master's non-cancelled, non-no-show appointments. With `appointmentId` (the client's
  own) its duration and master are used and its own time does not count as busy; else `serviceId` gives the duration
  (default 60 min) and `masterId` one master (default: every active master — employees with `isMaster`, all active
  employees when none is). A master off that day is left out (named «не работает в этот день» when asked for by
  `masterId`).
- `reschedule_appointment { appointmentId, startsAt }` — `startsAt` is studio-local «YYYY-MM-DD HH:MM» (an ISO instant
  with an offset is accepted). Only the linked client's own future `scheduled` / `confirmed` appointments; the new time
  must be ≥ 1 hour from now, ≤ 90 days ahead and inside the master's working time; duration and master are kept, the regular
  overlap check applies (`schedule_conflict` → the model offers another time), pending reminders are rebuilt and the
  staff chat gets «🔁 Клиент … перенёс запись №…» (before → after). The model calls it only after the client chose a
  time. Cancellations are handed to staff.
- `/bot/test` runs these tools without writing anything (no booking, no reschedule, no messages) and lists what would
  have happened.

#### Catalogs (inline buttons)
- The keyboard buttons «💎 Украшения» / «💉 Услуги и цены» and the `/catalog` command (jewelry) open a menu with
  inline buttons without an AI call (the button text is stored as the client's message, the menu as `[Каталог] …`).
  When there is nothing to show, the message goes to the AI as usual.
- Jewelry menu: the jewelry `CatalogCategory`s (staff order) that have active pieces in stock, plus «Другие» for
  pieces without a registered category, and «💉 Услуги и цены». Service menu: per service category its catalog
  categories in staff order («Пирсинг · Ухо»), then services without a group («Тату», or «Пирсинг · прочее» when the
  category has groups), and «💎 Украшения».
- A category opens a **carousel**: one message (photo + caption, or text when the item has no sendable picture) with
  «◀︎ 2 / 7 ▶︎» (wrapping around), and for jewelry «💍 Хочу это украшение» and «📂 Все украшения»; for services
  «📅 Записаться», «💎 Подходящие украшения» (when compatible pieces are in stock) and «📂 Все услуги». Paging edits
  the same message (photo, caption and buttons); between an item with a photo and one without, the message is
  replaced. The carousel is recomputed from the database on every press (a stale position is clamped).
- Jewelry caption (≤ 1024 chars): heading («💎 Украшения для «Хеликс»» / «💎 Лабрет»), name, material · thread ·
  thickness · colour · stone, «Подходит для: …», a short description and «В наличии:» with each size in stock and its
  price — never quantities. Compatible pieces of a service = active `jewelry` products linked to it
  (`Product.serviceIds` / `Service.jewelryIds`) that have a size in stock.
- «Хочу это украшение»: with two or more sizes in stock the buttons turn into size buttons («8 мм — 1 700 ₽», «◀︎
  Назад»); the choice is stored as the client's message «[Выбрано] Лабрет — 8 мм · 1 700 ₽ (украшение id 12, для
  «Хеликс»)» and the AI continues (offers to book, `create_booking_request` with the piece in the comment). «Записаться»
  stores «[Выбрано] Записаться: Хеликс · 3 000 ₽ (услуга id 5)» the same way. A size sold out meanwhile is refused.
- Button payloads (`callback_data`) carry everything they need (≤ 64 bytes), so buttons keep working after a restart;
  unknown or malformed ones answer «Эта кнопка устарела».

#### Reminder buttons
Every reminder carries «✅ Приду» and «🔁 Перенести». Only the client of the appointment, in the chat linked to their
card, can use them, and only while it is a future `scheduled` / `confirmed` appointment (otherwise the buttons are
removed: «Эта запись уже неактуальна»). A button under a message Telegram no longer shows to the bot (older than about
48 hours) answers with a new message instead of editing the old one.
- «✅ Приду» — `scheduled` → `confirmed` (pending reminders are rebuilt), the bot thanks the client, the staff chat
  gets «✅ … подтвердил(а) запись №…», and only «🔁 Перенести» stays under the reminder. Stored as «[Кнопка] ✅ Приду» +
  the bot's reply (no AI call).
- «🔁 Перенести» — stored as the client's message «[Кнопка] 🔁 Хочу перенести запись №…: <when> — <services>»; the AI
  continues with `my_appointments` / `free_slots` / `reschedule_appointment`.

#### Cancellation rules in the bot
The client AI knows `StudioSettings.cancellation` and tells it when a booking with a prepayment is made or asked about
(«Бесплатно отменить или перенести запись можно не позднее чем за 24 часа; при более поздней отмене предоплата не
возвращается, при неявке — тоже»; percents below 100 are named as a share). A reminder of an appointment that holds a
prepayment while a free cancellation is still possible adds «Бесплатно отменить можно до <day>, <time>». Rescheduling
through the bot is not limited by these rules.

#### Follow-ups
When a visit is completed (`complete`, or a sale that completes it), its client has Telegram linked and the bot
allowed, and the bot is on (`BotSettings.enabled`), the server schedules one of each, at `BotSettings.aftercareHour`
studio time on that day. They do not depend on `sendAftercare` and are not counted in `scheduledMessages`; a moment
already past is skipped:
- `healing_check` — after the largest `healingCheckDays` among the visit's catalog services (none set → none):
  «Здравствуйте, Анна! Прошла неделя после процедуры «Хеликс». Как заживает? 🙂» with the buttons «👍 Всё хорошо» and
  «🤔 Есть вопрос».
  - «👍 Всё хорошо» → stored «[Кнопка] 👍 Всё хорошо»; the bot thanks and, when `StudioSettings.reviewLinks` has any,
    asks for a review with a URL button per link («⭐ Яндекс Карты», «⭐ 2ГИС», «⭐ Google»).
  - «🤔 Есть вопрос» → stored «[Кнопка] 🤔 Есть вопрос по заживлению»; the bot asks to describe it and send a photo, the
    chat gets `needsAttention`, the staff chat is notified («🩹 Анна: вопрос по заживлению после «Хеликс», запись №…»).
- `jewelry_change` — after the smallest `jewelryChangeWeeks` among the visit's catalog services (none set → none):
  «Анна, прошло 6 недель после прокола «Хеликс» — самое время заменить украшение на подходящее по размеру. Записаться?»
  with «📅 Записаться» (stored «[Кнопка] 📅 Хочу записаться на замену украшения после «Хеликс»», the AI continues the
  booking) and «Позже» (a short reply, no AI).
Only the appointment's client, in the chat linked to their card, can use these buttons; the buttons are removed once
one is pressed («Позже» leaves «📅 Записаться»). After «🤔 Есть вопрос» the AI keeps answering the client as usual.
Completing a visit again schedules nothing new; a follow-up is cancelled if the client unlinks Telegram or turns the
bot off for themselves, and skipped if the visit is no longer `completed` when it is due.

#### Alerts
The staff chat (bound with `/staff`; else every staff chat) is told when something needs a person: the AI provider
refuses for lack of balance («⚠️ Закончился баланс ИИ (Polza) — бот отвечает заглушкой»), the AI fails several times
in a row, a daily backup or its off-site copy fails, free disk space runs low. Each kind at most once every 6 hours,
and once more when it recovers.

#### Formatting
Bot messages may use light Markdown that the server renders for Telegram (HTML parse mode): `**bold**`, a heading
line `# …` / `## …` (shown bold), list lines starting with `- ` or `* ` (shown as `• `), `` `code` ``. Everything else
is plain text (`<`, `>`, `&` are escaped). If Telegram rejects the markup the text is sent plain, markers stripped.
`BotMessage.text` keeps the raw text: apps render `**bold**` and strip the other markers. The AI is told to format
with short paragraphs, blank lines between blocks, «•» lists and **bold** only for the key facts (2–3 per client
message); staff answers use emoji block headers in bold.

#### Staff digests
Twice a day the bot sends every staff chat (a chat bound to an active employee) a summary, built from the data
without the AI (no AI cost), personalised with the employee's name (their own appointments are marked «вы»):
- **Morning** (`morningDigestAt`): today's appointments with time, client, services, master and total, the expected
  revenue; «Обратить внимание»: prepayments still awaited for today and tomorrow, unpaid past visits (last 30 days),
  open receipts left from earlier days, new booking requests, chats waiting for staff, low stock, the cash shift
  (yesterday's left open / none open), clients with a birthday among today's visits — or «Всё спокойно»; tomorrow's
  count and first appointment.
- **Evening** (`eveningDigestAt`): revenue of the day with the number of sales, the average check and the payment
  split, refunds; visits done / no-shows / cancelled; today's visits left unpaid; open receipts; the open cash shift
  with the expected cash («не забудьте закрыть»); tomorrow's appointments and prepayments still awaited for them.
Each digest is sent once per studio day when its time comes (not later than 3 hours after it, e.g. after a server
restart), only while the bot is running; it is stored in the chat as an `assistant` message.

#### Staff chats
- An employee is recognised when they share **their own** contact with the bot (the «📱 Поделиться номером» button):
  the contact's `user_id` must equal the sender's Telegram id (a forwarded contact card is refused, as Telegram sets
  `user_id` to the owner of the number) and the normalized phone must equal the phone of an **active** employee. The
  chat gets `employee`, is greeted as staff with a staff keyboard («📋 Что сегодня», «📊 Выручка за неделю», «📦 Что
  заканчивается», «💎 Украшения») and the staff chat is notified («🔑 … подключил(а) Telegram к боту как сотрудник»).
  No client card is created. Sharing any other phone later makes the chat a client chat again. The `/staff` group
  binding is never affected.
- Phones are compared normalized (see `normalizePhone`): Telegram's `phone_number` comes as `79931234567` or
  `+79931234567`, the profile phone may be written `8 (993) 123-45-67`, `+7 993 123 45 67`, `9931234567` — all match.
- **Sharing the phone is required.** Telegram never gives a bot the user's phone by itself, so a private chat that is
  neither linked to a client nor a staff chat can do nothing else until it shares its own contact:
  - `/start` appends to the greeting «Чтобы начать, нажмите «📱 Поделиться номером» внизу 👇 Так я найду вас в нашей
    базе или запишу как нового клиента. Сотрудников студии узнаю по номеру из профиля в MIKAN.»; the keyboard under
    the input field has only that button until the phone is shared.
  - Any other message (text, keyboard buttons, photos, files, voice, stickers) is stored for staff and answered — with
    no AI call — «Чтобы я мог помочь, нажмите «📱 Поделиться номером» внизу 👇 Это нужно сделать один раз.»; inline
    buttons answer «Сначала поделитесь номером — кнопка внизу 👇».
  - The shared phone of a client in the base links that client to the chat (and stores the Telegram nick); a new
    phone creates a client with the Telegram name (first / last name from the contact), the phone, the nick and source
    `telegram`. The client keyboard appears, and what the person asked before sharing the phone is answered by the AI
    right away. A deep link from the client card (`/start c…`) links the chat without the phone.
- The client AI, when
  someone says they work at the studio or asks to be recognised, points to the same button (a typed number does not
  count; a chat already linked to a client has no such button — staff then bind it in the app) and never claims to
  have recognised them.
- A refused contact leaves a `system` message in the chat: «Контакт не принят: прислана чужая карточка контакта
  (+7…), а не свой номер. …» or «Контакт не принят: не удалось распознать номер «…». …».
- Binding by hand: `PUT /bot/chats/:chatId/employee { employeeId }` (an active employee) makes any chat that
  employee's staff chat — for employees who never shared their phone. The bot sends the staff greeting with the staff
  keyboard (stored as a `system` message when delivered; a delivery failure is logged, the chat is bound anyway) and the
  staff chat gets «🔑 <name> подключён(а) к боту как сотрудник (вручную, @username)». Binding the chat to the employee
  it already belongs to sends nothing. `DELETE` undoes it.
- Staff mode is checked on every message: only while the employee is active (deactivation removes it at once).
  The AI then uses a staff system prompt (studio info and price list, the employee's name, the masters) and staff tools
  only — client tools are not offered, and client chats never get the staff tools (a client chat calling one gets
  «Неизвестный инструмент»):
  - `today {}` — today's appointments of all masters, sales today with the payment split, refunds, the cash shift and
    expected cash, new booking requests, chats waiting for staff, low stock count.
  - `appointments { from, to?, masterId?, clientQuery?, status? }` — studio-local dates (`to` inclusive, ≤ 62 days),
    every master: client and phone, master, service lines with prices, total, status, prepayment, payment, title, notes
    (`status`: an appointment status or `active`); up to 60 rows plus totals.
  - `client_info { query }` — up to 3 matching client cards (name, last name, phone, nick): contacts, Telegram, notes,
    visits, total spent, last visit, upcoming appointments, the last 10 services and purchases.
  - `analytics { from, to }` — `GET /reports/summary` for the studio-local days (≤ 400 days): revenue, sales,
    average check, refunds, payment split, services vs products, prepayments, top 10 services and products (with sizes),
    by master, new clients, completed appointments, no-shows, revenue by day (≤ 31 days).
  - `stock { query?, lowOnly? }` — active products of every kind with the stock of each size in units, minimums,
    prices; presence consumables by status; `lowOnly` — sizes at or below the minimum and presence status not `ok`.
  Staff answers may name quantities, money and any client's data. Staff chats are never escalated (`needsAttention`
  stays false); when the AI is off or the limit is reached they get «ИИ-помощник сейчас недоступен…».
- AI cost guards (daily and per-chat hourly limits) apply to staff chats too.

### Settings
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/settings/studio` | — | `StudioSettings` |
| PUT | `/settings/studio` | `StudioSettings` (any subset; omitted fields are kept) | `StudioSettings` · `400` for a malformed time or `workdayEnd` not after `workdayStart` |
| GET | `/settings/bot` | — | `BotSettings` |
| PUT | `/settings/bot` | `BotSettings` (any subset; read-only fields ignored) | `BotSettings` · `400` for invalid `reminderOffsets` (see BotSettings) |
