import { index, integer, primaryKey, sqliteTable, text } from 'drizzle-orm/sqlite-core';

/** All instants are stored as integer milliseconds since epoch (UTC). Money is integer rubles. */

const bool = (name: string) => integer(name, { mode: 'boolean' });
const ms = (name: string) => integer(name);

export const employees = sqliteTable('employees', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  name: text('name').notNull(),
  login: text('login').notNull().unique(),
  passwordHash: text('password_hash').notNull(),
  phone: text('phone'),
  color: text('color').notNull(),
  isMaster: bool('is_master').notNull().default(false),
  active: bool('active').notNull().default(true),
  /** Embedded in JWTs; bumped on password change / deactivation to revoke existing tokens. */
  tokenVersion: integer('token_version').notNull().default(0),
  createdAt: ms('created_at').notNull(),
  updatedAt: ms('updated_at').notNull(),
});

export const clients = sqliteTable(
  'clients',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    name: text('name').notNull(),
    nameSort: text('name_sort').notNull(),
    phone: text('phone').unique(),
    instagram: text('instagram'),
    birthday: text('birthday'),
    notes: text('notes'),
    source: text('source'),
    telegramChatId: integer('telegram_chat_id').unique(),
    telegramUsername: text('telegram_username'),
    botEnabled: bool('bot_enabled').notNull().default(true),
    archived: bool('archived').notNull().default(false),
    linkToken: text('link_token').unique(),
    searchText: text('search_text').notNull().default(''),
    createdAt: ms('created_at').notNull(),
    updatedAt: ms('updated_at').notNull(),
  },
  (t) => [index('clients_name_sort_idx').on(t.nameSort), index('clients_created_idx').on(t.createdAt)],
);

export const aftercareTemplates = sqliteTable('aftercare_templates', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  name: text('name').notNull(),
  category: text('category').notNull(),
  stepsJson: text('steps_json').notNull(),
  createdAt: ms('created_at').notNull(),
  updatedAt: ms('updated_at').notNull(),
});

export const services = sqliteTable('services', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  name: text('name').notNull(),
  category: text('category').notNull(),
  /** Free-text subgroup inside the category, e.g. «Ухо», «Лицо», «Доп. услуги». */
  groupName: text('group_name'),
  price: integer('price').notNull(),
  /** Upper bound of a price range («от 2 000 до 5 000 ₽», or «до 10 000 ₽» when `price` is 0). */
  priceMax: integer('price_max'),
  priceFrom: bool('price_from').notNull().default(false),
  durationMin: integer('duration_min').notNull(),
  description: text('description'),
  /** Schematic cover picture (upload path): the card/catalog image the bot also sends to clients. */
  imageUrl: text('image_url'),
  /** What the cover picture shows (prompt subject for regeneration); `null` = derived from name and description. */
  imagePrompt: text('image_prompt'),
  /** JSON array of upload paths: photos of real works. */
  photosJson: text('photos_json').notNull().default('[]'),
  /** JSON array of `{ name, price, durationMin | null }` — priced options such as «один / два». */
  variantsJson: text('variants_json').notNull().default('[]'),
  aftercareTemplateId: integer('aftercare_template_id').references(() => aftercareTemplates.id, {
    onDelete: 'set null',
  }),
  active: bool('active').notNull().default(true),
  sort: integer('sort').notNull().default(0),
  createdAt: ms('created_at').notNull(),
  updatedAt: ms('updated_at').notNull(),
});

export const products = sqliteTable(
  'products',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    kind: text('kind').notNull(),
    name: text('name').notNull(),
    nameSort: text('name_sort').notNull(),
    sku: text('sku'),
    category: text('category'),
    categorySort: text('category_sort').notNull().default(''),
    material: text('material'),
    size: text('size'),
    description: text('description'),
    price: integer('price').notNull(),
    cost: integer('cost'),
    quantity: integer('quantity').notNull().default(0),
    minQuantity: integer('min_quantity').notNull().default(0),
    unit: text('unit').notNull().default('шт'),
    photoUrl: text('photo_url'),
    active: bool('active').notNull().default(true),
    searchText: text('search_text').notNull().default(''),
    createdAt: ms('created_at').notNull(),
    updatedAt: ms('updated_at').notNull(),
  },
  (t) => [index('products_kind_idx').on(t.kind)],
);

export const cashShifts = sqliteTable(
  'cash_shifts',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    openedAt: ms('opened_at').notNull(),
    openedById: integer('opened_by_id')
      .notNull()
      .references(() => employees.id),
    openingCash: integer('opening_cash').notNull(),
    closedAt: ms('closed_at'),
    closedById: integer('closed_by_id').references(() => employees.id),
    closingCash: integer('closing_cash'),
    expectedCash: integer('expected_cash'),
    note: text('note'),
  },
  (t) => [index('cash_shifts_opened_idx').on(t.openedAt)],
);

export const appointments = sqliteTable(
  'appointments',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    clientId: integer('client_id')
      .notNull()
      .references(() => clients.id),
    masterId: integer('master_id')
      .notNull()
      .references(() => employees.id),
    serviceId: integer('service_id').references(() => services.id, { onDelete: 'set null' }),
    title: text('title'),
    startsAt: ms('starts_at').notNull(),
    endsAt: ms('ends_at').notNull(),
    status: text('status').notNull(),
    price: integer('price').notNull().default(0),
    deposit: integer('deposit').notNull().default(0),
    notes: text('notes'),
    saleId: integer('sale_id'),
    completedAt: ms('completed_at'),
    createdAt: ms('created_at').notNull(),
    updatedAt: ms('updated_at').notNull(),
  },
  (t) => [
    index('appointments_starts_idx').on(t.startsAt),
    index('appointments_master_idx').on(t.masterId, t.startsAt),
    index('appointments_client_idx').on(t.clientId),
  ],
);

/**
 * Services booked into an appointment (one row per service line). `name`, `price` and `durationMin` are snapshots,
 * so the history keeps what was actually done even after the catalog changes. `appointments.service_id` mirrors the
 * first line with a catalog service for older app builds.
 */
export const appointmentServices = sqliteTable(
  'appointment_services',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    appointmentId: integer('appointment_id')
      .notNull()
      .references(() => appointments.id, { onDelete: 'cascade' }),
    serviceId: integer('service_id').references(() => services.id, { onDelete: 'set null' }),
    name: text('name').notNull(),
    price: integer('price').notNull(),
    durationMin: integer('duration_min'),
    position: integer('position').notNull(),
  },
  (t) => [
    index('appointment_services_appointment_idx').on(t.appointmentId, t.position),
    index('appointment_services_service_idx').on(t.serviceId),
  ],
);

export const sales = sqliteTable(
  'sales',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    number: integer('number').notNull().unique(),
    clientId: integer('client_id').references(() => clients.id),
    employeeId: integer('employee_id')
      .notNull()
      .references(() => employees.id),
    appointmentId: integer('appointment_id').references(() => appointments.id),
    shiftId: integer('shift_id').references(() => cashShifts.id),
    subtotal: integer('subtotal').notNull(),
    discount: integer('discount').notNull().default(0),
    total: integer('total').notNull(),
    payCash: integer('pay_cash').notNull().default(0),
    payCard: integer('pay_card').notNull().default(0),
    payTransfer: integer('pay_transfer').notNull().default(0),
    /** Paid by an SBP QR code; only set from a confirmed `qr_payments` row, never directly by the app. */
    payQr: integer('pay_qr').notNull().default(0),
    status: text('status').notNull(),
    note: text('note'),
    refundedAt: ms('refunded_at'),
    refundReason: text('refund_reason'),
    refundShiftId: integer('refund_shift_id').references(() => cashShifts.id),
    refundedById: integer('refunded_by_id').references(() => employees.id),
    createdAt: ms('created_at').notNull(),
  },
  (t) => [
    index('sales_created_idx').on(t.createdAt),
    index('sales_client_idx').on(t.clientId),
    index('sales_shift_idx').on(t.shiftId),
    index('sales_refund_shift_idx').on(t.refundShiftId),
  ],
);

export const saleItems = sqliteTable(
  'sale_items',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    saleId: integer('sale_id')
      .notNull()
      .references(() => sales.id, { onDelete: 'cascade' }),
    type: text('type').notNull(),
    productId: integer('product_id').references(() => products.id),
    serviceId: integer('service_id').references(() => services.id),
    name: text('name').notNull(),
    quantity: integer('quantity').notNull(),
    price: integer('price').notNull(),
    total: integer('total').notNull(),
  },
  (t) => [index('sale_items_sale_idx').on(t.saleId)],
);

/**
 * A dynamic SBP QR code shown at checkout. The sale is created on the server only once the bank confirms the
 * payment, from the cart stored in `saleInputJson`, so a paid QR maps to exactly one sale.
 */
export const qrPayments = sqliteTable(
  'qr_payments',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    /** `tochka` */
    provider: text('provider').notNull(),
    /** The bank's QR id (Tochka `qrcId`). */
    externalId: text('external_id').notNull().unique(),
    /** The link encoded into the QR image (`https://qr.nspk.ru/...`). */
    payload: text('payload').notNull(),
    amount: integer('amount').notNull(),
    /** `pending` | `paid` | `expired` | `cancelled` */
    status: text('status').notNull(),
    saleInputJson: text('sale_input_json').notNull(),
    saleId: integer('sale_id').references(() => sales.id),
    /** For staff: a declined attempt / unreachable bank while pending, or why paid money was not sold. */
    error: text('error'),
    employeeId: integer('employee_id')
      .notNull()
      .references(() => employees.id),
    expiresAt: ms('expires_at').notNull(),
    /** Last successful bank check. */
    checkedAt: ms('checked_at'),
    paidAt: ms('paid_at'),
    createdAt: ms('created_at').notNull(),
    updatedAt: ms('updated_at').notNull(),
  },
  (t) => [index('qr_payments_status_idx').on(t.status, t.expiresAt)],
);

export const stockMovements = sqliteTable(
  'stock_movements',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    productId: integer('product_id')
      .notNull()
      .references(() => products.id),
    delta: integer('delta').notNull(),
    quantityAfter: integer('quantity_after').notNull(),
    type: text('type').notNull(),
    note: text('note'),
    saleId: integer('sale_id').references(() => sales.id),
    appointmentId: integer('appointment_id').references(() => appointments.id),
    employeeId: integer('employee_id').references(() => employees.id),
    createdAt: ms('created_at').notNull(),
  },
  (t) => [index('stock_movements_product_idx').on(t.productId, t.id), index('stock_movements_type_idx').on(t.type)],
);

export const cashOperations = sqliteTable(
  'cash_operations',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    shiftId: integer('shift_id')
      .notNull()
      .references(() => cashShifts.id),
    type: text('type').notNull(),
    amount: integer('amount').notNull(),
    reason: text('reason').notNull(),
    employeeId: integer('employee_id')
      .notNull()
      .references(() => employees.id),
    createdAt: ms('created_at').notNull(),
  },
  (t) => [index('cash_operations_shift_idx').on(t.shiftId)],
);

export const botChats = sqliteTable('bot_chats', {
  chatId: integer('chat_id').primaryKey(),
  clientId: integer('client_id').references(() => clients.id, { onDelete: 'set null' }),
  telegramName: text('telegram_name'),
  username: text('username'),
  aiPaused: bool('ai_paused').notNull().default(false),
  needsAttention: bool('needs_attention').notNull().default(false),
  unreadCount: integer('unread_count').notNull().default(0),
  createdAt: ms('created_at').notNull(),
  updatedAt: ms('updated_at').notNull(),
});

export const botMessages = sqliteTable(
  'bot_messages',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    chatId: integer('chat_id')
      .notNull()
      .references(() => botChats.chatId),
    role: text('role').notNull(),
    text: text('text').notNull(),
    employeeId: integer('employee_id').references(() => employees.id),
    createdAt: ms('created_at').notNull(),
  },
  (t) => [index('bot_messages_chat_idx').on(t.chatId, t.id)],
);

export const scheduledMessages = sqliteTable(
  'scheduled_messages',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    chatId: integer('chat_id').notNull(),
    clientId: integer('client_id')
      .notNull()
      .references(() => clients.id),
    appointmentId: integer('appointment_id').references(() => appointments.id),
    kind: text('kind').notNull(),
    sendAt: ms('send_at').notNull(),
    text: text('text').notNull(),
    status: text('status').notNull(),
    sentAt: ms('sent_at'),
    error: text('error'),
    attempts: integer('attempts').notNull().default(0),
    createdAt: ms('created_at').notNull(),
  },
  (t) => [
    index('scheduled_status_send_idx').on(t.status, t.sendAt),
    index('scheduled_appointment_idx').on(t.appointmentId),
  ],
);

export const bookingRequests = sqliteTable('booking_requests', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  chatId: integer('chat_id'),
  clientId: integer('client_id').references(() => clients.id, { onDelete: 'set null' }),
  contactName: text('contact_name').notNull(),
  phone: text('phone'),
  serviceName: text('service_name'),
  preferredTime: text('preferred_time'),
  comment: text('comment'),
  status: text('status').notNull(),
  createdAt: ms('created_at').notNull(),
  updatedAt: ms('updated_at').notNull(),
});

export const knowledgeEntries = sqliteTable('knowledge_entries', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  title: text('title').notNull(),
  content: text('content').notNull(),
  active: bool('active').notNull().default(true),
  sort: integer('sort').notNull().default(0),
  createdAt: ms('created_at').notNull(),
  updatedAt: ms('updated_at').notNull(),
});

/** Key-value store for studio/bot settings and small runtime state (staff chat, staff code, bot username). */
export const settings = sqliteTable('settings', {
  key: text('key').primaryKey(),
  value: text('value').notNull(),
  updatedAt: ms('updated_at').notNull(),
});

/** One row per AI pipeline run, used for cost guards (per-chat hourly, global daily). */
export const aiUsage = sqliteTable(
  'ai_usage',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    chatId: integer('chat_id'),
    outcome: text('outcome').notNull(),
    inputTokens: integer('input_tokens').notNull().default(0),
    outputTokens: integer('output_tokens').notNull().default(0),
    cacheReadTokens: integer('cache_read_tokens').notNull().default(0),
    createdAt: ms('created_at').notNull(),
  },
  (t) => [index('ai_usage_created_idx').on(t.createdAt), index('ai_usage_chat_idx').on(t.chatId, t.createdAt)],
);

/**
 * Responses of write requests sent with an `Idempotency-Key` header, kept ~24 h so a retried request
 * (lost response, timeout) returns the original result instead of being applied twice.
 */
export const idempotencyKeys = sqliteTable(
  'idempotency_keys',
  {
    key: text('key').notNull(),
    employeeId: integer('employee_id').notNull(),
    /** `METHOD /path` of the original request, e.g. `POST /api/sales/12/refund`. */
    endpoint: text('endpoint').notNull(),
    /** SHA-256 of the endpoint and the canonical JSON body; a reused key with another body is a conflict. */
    requestHash: text('request_hash').notNull(),
    responseJson: text('response_json').notNull(),
    createdAt: ms('created_at').notNull(),
  },
  (t) => [primaryKey({ columns: [t.employeeId, t.key] }), index('idempotency_keys_created_idx').on(t.createdAt)],
);
