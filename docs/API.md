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
  `conflict` (409), `insufficient_stock` (409), `schedule_conflict` (409), `rate_limited` (429), `internal` (500).
  `message` is always human-readable Russian; the app shows it as is.
- All employees have identical permissions.
- Idempotency: `POST /sales`, `POST /sales/:id/refund`, `POST /cash/operations` and `POST /products/:id/movements`
  accept an optional `Idempotency-Key: <UUID>` header. The app generates one key per user action and resends the
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
{ "id": 1, "name": "Иван Петров", "phone": "+79991234567", "telegramLinked": true } // ClientRef
{ "id": 3, "name": "Прокол мочки", "category": "piercing" }             // ServiceRef
```

### Client
```json
{ "id": 1, "name": "Иван Петров", "phone": "+79991234567", "instagram": "ivan.p",
  "birthday": "1995-04-12", "notes": "Аллергия на никель", "source": "instagram",
  "telegramLinked": true, "telegramUsername": "ivanp", "botEnabled": true,
  "archived": false, "createdAt": "...", "updatedAt": "...",
  "stats": null }
```
- `source`: free text; app offers `instagram`, `telegram`, `рекомендация`, `с улицы`, `другое`.
- `botEnabled`: whether the bot may send this client aftercare and reminders.
- `stats` is `null` in lists and filled in `GET /clients/:id`:
  `{ "visits": 3, "totalSpent": 25000, "lastVisitAt": "..." | null, "upcomingAppointments": 1 }`
  (`visits` = completed appointments; `totalSpent` = sum of non-refunded sales totals).

### Service
```json
{ "id": 1, "name": "Прокол мочки", "category": "piercing", "price": 2500, "priceFrom": false,
  "durationMin": 30, "description": "Текст для бота и сотрудников", "aftercareTemplateId": 2,
  "active": true, "sort": 0 }
```
`category`: `tattoo` | `piercing` | `other`. `priceFrom: true` means "от N ₽" (final price set per appointment).

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
{ "id": 1, "kind": "jewelry", "name": "Лабрет", "sku": "LB-12-08", "category": "Лабрет",
  "material": "Титан G23", "size": "1.2×8 мм", "description": "...",
  "price": 1500, "cost": 600, "quantity": 12, "minQuantity": 3, "unit": "шт",
  "photoUrl": "/uploads/3f1c….jpg", "active": true, "lowStock": false,
  "createdAt": "...", "updatedAt": "..." }
```
- `kind`: `jewelry` (sold to clients, visible to the bot) | `consumable` (used in procedures, not sold).
- `quantity` is maintained only through stock movements (never set directly by PATCH).
- `photoUrl`: path relative to the server origin (app prefixes the host) or `null`.
- `lowStock` (derived, output only): `quantity <= minQuantity`.

### StockMovement
```json
{ "id": 1, "productId": 1, "productName": "Лабрет", "delta": -1, "quantityAfter": 11,
  "type": "sale", "note": null, "saleId": 5, "appointmentId": null,
  "employee": { "id": 1, "name": "Анна", "color": "#FF7A1A" }, "createdAt": "..." }
```
`type`: `receipt` (приход) | `sale` | `return` | `writeoff` (списание) | `usage` (расход на процедуру) | `adjustment` (инвентаризация).

### Appointment
```json
{ "id": 1, "client": { ClientRef }, "master": { EmployeeRef }, "service": { ServiceRef } | null,
  "title": "Тату на предплечье, эскиз согласован", "startsAt": "...", "endsAt": "...",
  "status": "scheduled", "price": 8000, "deposit": 2000, "notes": "...",
  "saleId": null, "completedAt": null, "createdAt": "...", "updatedAt": "..." }
```
`status`: `scheduled` | `confirmed` | `completed` | `cancelled` | `no_show`.
`deposit` — prepayment already received (informational; see Sales). `saleId` — the sale that paid for it.

### Sale
```json
{ "id": 1, "number": 17, "client": { ClientRef } | null, "employee": { EmployeeRef },
  "appointmentId": null, "shiftId": 3,
  "items": [ { "id": 1, "type": "product", "productId": 1, "serviceId": null,
               "name": "Лабрет", "quantity": 1, "price": 1500, "total": 1500 } ],
  "subtotal": 1500, "discount": 0, "total": 1500,
  "payments": { "cash": 1500, "card": 0, "transfer": 0 },
  "status": "completed", "note": null, "refundedAt": null, "refundReason": null, "createdAt": "..." }
```
- `type`: `product` (requires `productId`; decrements stock) | `service` (`serviceId` optional; `name` required when no `serviceId`).
- `number`: sequential human-readable receipt number.
- `status`: `completed` | `refunded`.

### CashShift
```json
{ "id": 3, "openedAt": "...", "openedBy": { EmployeeRef }, "openingCash": 5000,
  "closedAt": null, "closedBy": null, "closingCash": null, "note": null,
  "expectedCash": 7500, "difference": null,
  "summary": { "salesCount": 3, "revenue": 10000, "cash": 2500, "card": 5000, "transfer": 2500,
               "refunds": 0, "cashRefunds": 0, "cashIn": 0, "cashOut": 0 },
  "operations": [ CashOperation ] }
```
- `expectedCash = openingCash + summary.cash − summary.cashRefunds + summary.cashIn − summary.cashOut` (computed live while open; frozen at close).
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
  "instagram": "", "website": "", "about": "", "timezone": "Europe/Moscow" }
```

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
| GET | `/badges` | `{ "unreadChats": 2, "needsAttention": 1, "newBookingRequests": 1, "lowStock": 3 }` (the app polls every 30 s) |
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
| GET | `/clients?search=&archived=false&limit=&offset=` | — | `{ items: [Client], total }` — search matches name, phone digits, instagram, telegram username; sorted by name |
| GET | `/clients/:id` | — | `Client` with `stats` |
| POST | `/clients` | `{ name, phone?, instagram?, birthday?, notes?, source?, botEnabled? }` | `Client` · `409 conflict` if phone already belongs to another client (message names that client) |
| PATCH | `/clients/:id` | same fields + `archived` | `Client` |
| GET | `/clients/:id/history` | — | `{ appointments: [Appointment], sales: [Sale] }` newest first |
| GET | `/clients/:id/chat` | — | `{ "chat": BotChat \| null }` — the client's Telegram bot chat (the linked chat, else the latest chat attributed to the client); `null` if the client has never written to the bot |
| POST | `/clients/:id/telegram-link` | — | `{ "url": "https://t.me/<bot>?start=c<token>" }` — opening it links the Telegram chat to this client |

### Services
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/services?includeInactive=true` | — | `{ items: [Service] }` sorted by `sort`, then name |
| POST | `/services` | `{ name, category, price, priceFrom?, durationMin, description?, aftercareTemplateId?, active?, sort? }` | `Service` |
| PATCH | `/services/:id` | any of the above | `Service` |

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
| POST | `/products` | `{ kind, name, sku?, category?, material?, size?, description?, price, cost?, minQuantity?, unit?, photoUrl?, active?, initialQuantity? }` | `Product` (`initialQuantity > 0` creates a `receipt` movement) |
| PATCH | `/products/:id` | any of the above except `quantity`/`initialQuantity` | `Product` |
| POST | `/products/:id/movements` | `{ type: "receipt"\|"writeoff"\|"usage"\|"adjustment", quantity, note? }` | `{ product: Product, movement: StockMovement }` · accepts `Idempotency-Key` |
| GET | `/products/:id/movements?limit=&offset=` | — | `{ items: [StockMovement], total }` |
| GET | `/stock/movements?type=&limit=&offset=` | — | `{ items: [StockMovement], total }` newest first |

Movement `quantity` semantics: `receipt` — positive amount added; `writeoff`/`usage` — positive amount removed;
`adjustment` — the **new absolute quantity** after a stock count (server computes `delta`). Stock may not go below 0
(`409 insufficient_stock`).

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
| POST | `/appointments` | `{ clientId, masterId, serviceId?, title?, startsAt, endsAt, price?, deposit?, notes?, status?, force? }` | `Appointment` |
| PATCH | `/appointments/:id` | any of the above (incl. `status`) + `force?` | `Appointment` |
| POST | `/appointments/:id/complete` | `{ sendAftercare: true, aftercareTemplateId?, consumables?: [{ productId, quantity }] }` | `{ appointment: Appointment, scheduledMessages: 3 }` |

- `price` defaults to the service price; `endsAt` must be after `startsAt`.
- Overlap check: if the master already has a non-cancelled, non-no-show appointment overlapping the time, respond
  `409 schedule_conflict` (message names the conflicting client and time) unless `force: true`.
- `complete`: sets `status = completed`, `completedAt = now`; writes `usage` movements for `consumables`; when
  `sendAftercare` and the client has Telegram linked and `botEnabled`, schedules the aftercare template steps
  (template = `aftercareTemplateId` ?? service's template). Cancels pending reminders of this appointment.
- Creating/rescheduling an appointment for a Telegram-linked client schedules a reminder
  `reminderHoursBefore` hours before `startsAt` (if `remindersEnabled` and that moment is in the future).
  Cancelling / no-show / rescheduling cancels or replaces pending reminders.

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
  "items": [ { "type": "product", "productId": 1, "quantity": 1, "price": 1500 },
             { "type": "service", "serviceId": 3, "name": "Прокол мочки", "quantity": 1, "price": 2500 } ],
  "discount": 500, "payments": { "cash": 1500, "card": 2000, "transfer": 0 }, "note": null }
```
- `price` per item is the unit price actually charged (defaults to catalog price if omitted).
- `subtotal = Σ quantity × price`; `total = subtotal − discount` (`0 ≤ discount ≤ subtotal`);
  `payments.cash + payments.card + payments.transfer` must equal `total` (`400` otherwise).
- Product items decrement stock (`sale` movements); insufficient stock → `409 insufficient_stock`
  ("Недостаточно на складе: Лабрет (осталось 0)"). Whole sale is one transaction.
- With `appointmentId`, the appointment gets `saleId` (and is marked `completed` if not already, without aftercare).
- Deposit handling: the app pre-fills `payments.transfer` (or the method the deposit was taken by) with
  `appointment.deposit`, so revenue is recognised once, at checkout.
- Refund: marks `refunded`, returns product stock (`return` movements) when `restock`; a cash refund is attributed
  to the currently open shift (`summary.cashRefunds`).

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
  "payments": { "cash": 30000, "card": 70000, "transfer": 20000 },
  "servicesRevenue": 90000, "productsRevenue": 30000,
  "byDay": [ { "date": "2026-10-01", "revenue": 8000, "salesCount": 3 } ],
  "topProducts": [ { "productId": 1, "name": "Лабрет", "quantity": 7, "revenue": 10500 } ],
  "topServices": [ { "serviceId": 3, "name": "Прокол мочки", "quantity": 12, "revenue": 30000 } ],
  "byMaster": [ { "employee": { EmployeeRef }, "appointmentsCompleted": 10, "revenue": 50000 } ],
  "newClients": 14, "appointmentsCompleted": 35, "noShows": 2 }
```
Revenue excludes refunded sales. `byDay` uses the studio timezone and lists every day in range (zeros included).
`byMaster.revenue` = sales linked to that master's appointments. Item-level revenue is split proportionally to the
sale discount (rounded to whole rubles).

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

### Settings
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/settings/studio` | — | `StudioSettings` |
| PUT | `/settings/studio` | `StudioSettings` | `StudioSettings` |
| GET | `/settings/bot` | — | `BotSettings` |
| PUT | `/settings/bot` | `BotSettings` (read-only fields ignored) | `BotSettings` |
