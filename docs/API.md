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
- All employees have identical permissions.
- Idempotency: `POST /sales`, `POST /sales/:id/refund`, `POST /cash/operations`, `POST /products/:id/movements`,
  `POST /products/:id/movements/batch`
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
  "isMaster": true, "active": true, "createdAt": "..." }
```
`color` — hex used for the master's appointments in the calendar. `isMaster` — performs procedures (shows in master pickers).

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
  "aftercareTemplateId": 2, "freshProcedure": true, "active": true, "sort": 0 }
```
- `freshProcedure` — the service leaves a fresh wound: «Свежий прокол» (piercing), «Свежее тату» (tattoo), «Нужна
  памятка по уходу» (other). Aftercare memos are sent only for appointments with at least one such service (see
  `complete`); a jewelry change, cleaning or consultation keeps it `false`. On create it defaults to whether
  `aftercareTemplateId` is set (older builds do not send it); PATCH without it keeps the value.
- `depositAmount`: prepayment required to book this service (whole rubles); `0` — no prepayment. An appointment's
  `depositRequired` defaults to the sum over its lines' catalog services (a service booked twice counts twice).
- `category`: `tattoo` | `piercing` | `other` (drives the default aftercare template and icons).
- `group`: free-text subgroup inside the category («Лицо», «Ухо», «Тело», «Доп. услуги», …) or `null`;
  lists are grouped by category, then group.
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

### Product (jewelry and consumables)
```json
{ "id": 1, "kind": "jewelry", "name": "Лабрет", "sku": "LB-12", "category": "Лабрет",
  "material": "Титан ASTM F136", "threadType": "internal", "thicknessMm": 1.2,
  "color": "Серебристый", "stone": "Фианит", "supplier": "Industrial Strength",
  "description": "...", "price": 1500, "cost": 600, "unit": "шт",
  "photos": ["/uploads/3f1c….jpg", "/uploads/9a0b….jpg"], "photoUrl": "/uploads/3f1c….jpg",
  "serviceIds": [3, 7], "active": true,
  "variants": [
    { "id": 1, "name": "6 мм", "sku": null, "price": null, "cost": null,
      "quantity": 4, "minQuantity": 1, "lowStock": false },
    { "id": 5, "name": "8 мм", "sku": "LB-12-08", "price": 1700, "cost": 700,
      "quantity": 0, "minQuantity": 1, "lowStock": true } ],
  "quantity": 4, "minQuantity": 2, "lowStock": true, "size": "6 мм, 8 мм",
  "createdAt": "...", "updatedAt": "..." }
```
- `kind`: `jewelry` (sold to clients, visible to the bot) | `consumable` (used in procedures, not sold).
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
  "type": "sale", "note": null, "saleId": 5, "appointmentId": null,
  "employee": { "id": 1, "name": "Анна", "color": "#FF7A1A" }, "createdAt": "..." }
```
`type`: `receipt` (приход) | `sale` | `return` | `writeoff` (списание) | `usage` (расход на процедуру) | `adjustment` (инвентаризация).
`variantName` — the size's current name (`""` for a product without sizes); `quantityAfter` — the stock of that size
after the movement.

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
  "saleId": null, "paidOutside": false, "completedAt": null, "createdAt": "...", "updatedAt": "..." }
```
`status`: `scheduled` | `confirmed` | `completed` | `cancelled` | `no_show`. `saleId` — the sale that paid for it.
`paidOutside` — the visit was paid before MIKAN (carried over from YCLIENTS) and has no sale here: apps show it as
paid and do not offer to take payment; `POST /sales` with its `appointmentId` → `409 conflict`. Set by the server
maintenance script `close-imported-appointments` (dry run by default; `--apply` closes past unpaid imported visits as
`completed` + `paidOutside`).
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
{ "chatId": 123456789, "client": { ClientRef } | null, "telegramName": "Иван", "username": "ivanp",
  "aiPaused": false, "needsAttention": false, "unreadCount": 2,
  "lastMessage": { BotMessage } | null, "updatedAt": "..." }
```
`needsAttention` — the bot handed the conversation to staff (cleared when staff replies or marks read).

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
`kind`: `aftercare` | `reminder`. `status`: `pending` | `sent` | `failed` | `cancelled`.

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
  "workdayStart": "10:00", "workdayEnd": "21:00" }
```
- `workdayStart` / `workdayEnd` — working hours «с» / «до», `"HH:MM"` in the studio `timezone` (`"24:00"` = midnight;
  the end must be later than the start). The app's calendar (day / 3 days / week) starts and ends at these hours.
  They are **not** a booking limit: staff may book or move appointments to any time, the server accepts them, and
  the calendar widens its range to show appointments outside the hours. Defaults `11:00`–`21:00`; settings saved
  before these fields existed take them from the first `HH:MM–HH:MM` range in `workingHours`.
- `workingHours` — free text for clients (the bot quotes it); when empty, the bot names `workdayStart`–`workdayEnd`.

### BotSettings
```json
{ "enabled": true, "aiEnabled": true, "greeting": "...", "extraInstructions": "",
  "aftercareHour": 12, "remindersEnabled": true, "reminderHoursBefore": 24,
  "botUsername": "mikan_studio_bot", "staffChatBound": false, "aiConfigured": true }
```
`botUsername`, `staffChatBound`, `aiConfigured` are read-only (ignored on PUT).

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
| GET | `/badges` | `{ "unreadChats": 2, "needsAttention": 1, "newBookingRequests": 1, "lowStock": 3 }` (the app polls every 30 s; `lowStock` — active products with at least one low size) |
| GET | `/dashboard` | `{ "date": "2026-10-15", "appointments": [Appointment] (today, studio tz, excl. cancelled), "revenueToday": 12000, "salesCountToday": 4, "openShift": CashShift \| null, "badges": {…same as /badges} }` |

### Employees
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/employees?includeInactive=true` | — | `{ items: [Employee] }` (active only by default) |
| POST | `/employees` | `{ name, login, password (≥6), phone?, color?, isMaster }` | `Employee` · `409 conflict` if login taken |
| PATCH | `/employees/:id` | any of `{ name, login, password, phone, color, isMaster, active }` | `Employee` · cannot deactivate yourself (`400`) |

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
| POST | `/services` | `{ name, category, group?, price, priceMax?, priceFrom?, durationMin, description?, imageUrl?, imagePrompt?, photos?, variants?, depositAmount?, aftercareTemplateId?, active?, sort? }` | `Service` |
| PATCH | `/services/:id` | any of the above | `Service` |
| GET | `/services/:id/history?limit=&offset=` | — | `{ items: [HistoryEntry], total }` — who got this service and when, newest first |
| POST | `/services/:id/image/generate` | `{ prompt? }` (≤ 1000 chars) | `Service` with a new `imageUrl` — generates the schematic cover with AI (Polza Media API, ~1–2 min; apps use a 4-minute timeout). A non-empty `prompt` is used and saved as `imagePrompt`; `prompt: ""` / `null` resets it (generates from the name/description and saves `imagePrompt = null`); without `prompt` the saved `imagePrompt` (or name/description) is used. Only `imageUrl` (and `imagePrompt` when `prompt` is sent) change, so edits made during generation are kept. `409 conflict` when the AI key (`AI_API_KEY` + `AI_BASE_URL`) is not configured or a generation for this service is already running, `502 upstream_error` when generation fails (message says why). The previous picture file is kept. |

### Aftercare templates
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/aftercare-templates` | — | `{ items: [AftercareTemplate] }` |
| POST | `/aftercare-templates` | `{ name, category, steps: [{ dayOffset ≥ 0, text }] (≥1) }` | `AftercareTemplate` |
| PATCH | `/aftercare-templates/:id` | any of the above | `AftercareTemplate` |
| DELETE | `/aftercare-templates/:id` | — | `204` (services referencing it get `aftercareTemplateId = null`) |

### Products & stock
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/products?kind=jewelry&search=&lowStock=true&includeInactive=true` | — | `{ items: [Product] }` sorted by category, name |
| GET | `/products/:id` | — | `Product` |
| POST | `/products` | see below | `Product` |
| PATCH | `/products/:id` | any of the POST fields | `Product` |
| POST | `/products/:id/movements` | `{ type: "receipt"\|"writeoff"\|"usage"\|"adjustment", variantId?, quantity, note? }` | `{ product: Product, movement: StockMovement }` · accepts `Idempotency-Key` |
| POST | `/products/:id/movements/batch` | `{ type, note?, lines: [{ variantId, quantity }] }` | `{ product: Product, movements: [StockMovement] }` · accepts `Idempotency-Key` |
| GET | `/products/:id/movements?variantId=&limit=&offset=` | — | `{ items: [StockMovement], total }` |
| GET | `/products/:id/history?variantId=&limit=&offset=` | — | `{ items: [HistoryEntry], total }` — who bought this product (or this size) and when, newest first |
| GET | `/stock/movements?type=&limit=&offset=` | — | `{ items: [StockMovement], total }` newest first |

- `search` matches the name, SKUs (product and sizes), category, material, colour, stone, supplier and size names.
  `lowStock=true` — products with at least one low size.

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

Movements:
- `quantity` semantics: `receipt` — positive amount added; `writeoff`/`usage` — positive amount removed;
  `adjustment` — the **new absolute quantity** of the size after a stock count (server computes `delta`). Stock may not
  go below 0 (`409 insufficient_stock`, «Недостаточно на складе: Лабрет — 8 мм (осталось 2)»).
- `variantId` must be a current size of the product (`400` otherwise). Without it (older builds) the only size is
  used; for a product with several sizes → `409 conflict` «У «Лабрет» несколько размеров — обновите приложение MIKAN,
  чтобы провести операцию по размеру».
- `batch` records one operation for several sizes in one transaction (a delivery, a stock count of all sizes):
  1–50 lines with distinct `variantId`s. `receipt` / `writeoff` / `usage` lines need `quantity > 0`; `adjustment`
  lines whose count equals the current stock are skipped, and a count that changes nothing → `400` «Остатки не
  изменились». `movements` are in line order.

### Uploads
| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/uploads` | `multipart/form-data`, field `file` (JPEG/PNG/HEIC/WebP, ≤ 10 MB) | `{ "url": "/uploads/<uuid>.<ext>" }` |

Files are served publicly at `GET /uploads/<name>` (outside `/api`, no auth; names are unguessable UUIDs).

### Appointments
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/appointments?from=&to=&masterId=&clientId=&status=` | — | `{ items: [Appointment] }` overlapping `[from, to)`, sorted by `startsAt` |
| GET | `/appointments/:id` | — | `Appointment` |
| POST | `/appointments` | `{ clientId, masterId, services?, serviceId?, title?, startsAt, endsAt?, price?, depositRequired?, notes?, status?, force? }` | `Appointment` |
| PATCH | `/appointments/:id` | any of the above (incl. `status`) + `force?` | `Appointment` |
| POST | `/appointments/:id/complete` | `{ sendAftercare: true, aftercareTemplateId?, consumables?: [{ productId, variantId?, quantity }] }` | `{ appointment: Appointment, scheduledMessages: 3 }` |
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
  appointments before opening or after closing are accepted.
- `complete`: sets `status = completed`, `completedAt = now`; writes `usage` movements for `consumables` (the only
  size of the product unless `variantId` is given; a product with several sizes needs `variantId`: `409 conflict` asking
  to update the app otherwise); when
  `sendAftercare`, the client has Telegram linked and `botEnabled`, **and at least one of the appointment's catalog
  services has `freshProcedure`**, schedules the aftercare template steps (template = `aftercareTemplateId` ?? the
  template of the first such service that has one). An appointment without a fresh procedure (only a jewelry change,
  say, or no catalog services) gets no memo whatever the app sends: `scheduledMessages: 0`. Cancels pending reminders
  of this appointment.
- Creating/rescheduling an appointment for a Telegram-linked client schedules a reminder
  `reminderHoursBefore` hours before `startsAt` (if `remindersEnabled` and that moment is in the future).
  Cancelling / no-show / rescheduling cancels or replaces pending reminders.

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
  "discount": 500, "payments": { "cash": 1500, "card": 0, "transfer": 0, "qr": 0, "deposit": 2000 }, "note": null }
```
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

### Bot (Telegram + AI)
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/bot/chats` | — | `{ items: [BotChat] }` sorted by `updatedAt` desc |
| GET | `/bot/chats/:chatId/messages?beforeId=&limit=50` | — | `{ items: [BotMessage] }` ascending by time (the page *before* `beforeId`) |
| POST | `/bot/chats/:chatId/messages` | `{ text }` | `BotMessage` (role `staff`, delivered to Telegram immediately; clears `needsAttention`) |
| POST | `/bot/chats/:chatId/read` | — | `204` (unreadCount → 0, needsAttention → false) |
| PATCH | `/bot/chats/:chatId` | `{ aiPaused }` | `BotChat` |
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
thickness, price and the sizes in stock.

### Settings
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/settings/studio` | — | `StudioSettings` |
| PUT | `/settings/studio` | `StudioSettings` (any subset; omitted fields are kept) | `StudioSettings` · `400` for a malformed time or `workdayEnd` not after `workdayStart` |
| GET | `/settings/bot` | — | `BotSettings` |
| PUT | `/settings/bot` | `BotSettings` (read-only fields ignored) | `BotSettings` |
