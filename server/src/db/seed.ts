import bcrypt from 'bcryptjs';
import { count } from 'drizzle-orm';
import type { Config } from '../config.js';
import { ensureDefaultSettings } from '../domain/settings.js';
import type { Db } from './client.js';
import { aftercareTemplates, employees, knowledgeEntries } from './schema.js';
import { KNOWLEDGE_DRAFTS, PIERCING_TEMPLATE, TATTOO_TEMPLATE } from './seed-content.js';

export const BCRYPT_ROUNDS = 10;
export const DEFAULT_EMPLOYEE_COLOR = '#FF7A1A';
/** Calendar colors handed out to new employees in turn when no color is chosen. */
export const EMPLOYEE_PALETTE = ['#FF7A1A', '#5E5CE6', '#30B0C7', '#34C759', '#FF375F', '#BF5AF2', '#FFCC00', '#0A84FF'];

const isEmpty = (db: Db, table: typeof employees | typeof aftercareTemplates | typeof knowledgeEntries) =>
  (db.select({ n: count() }).from(table).get()?.n ?? 0) === 0;

/** Idempotent first-run seed. Never invents services or product prices. */
export function seedDatabase(db: Db, config: Pick<Config, 'admin'>): void {
  db.transaction((tx) => {
    const now = Date.now();
    ensureDefaultSettings(tx);
    if (isEmpty(db, employees)) {
      tx.insert(employees)
        .values({
          name: config.admin.name,
          login: config.admin.login.trim().toLowerCase(),
          passwordHash: bcrypt.hashSync(config.admin.password, BCRYPT_ROUNDS),
          color: DEFAULT_EMPLOYEE_COLOR,
          isMaster: true,
          active: true,
          createdAt: now,
          updatedAt: now,
        })
        .run();
    }
    if (isEmpty(db, aftercareTemplates)) {
      tx.insert(aftercareTemplates)
        .values(
          [TATTOO_TEMPLATE, PIERCING_TEMPLATE].map((t) => ({
            name: t.name,
            category: t.category,
            stepsJson: JSON.stringify(t.steps),
            createdAt: now,
            updatedAt: now,
          })),
        )
        .run();
    }
    if (isEmpty(db, knowledgeEntries)) {
      tx.insert(knowledgeEntries)
        .values(KNOWLEDGE_DRAFTS.map((k, i) => ({ ...k, active: true, sort: i, createdAt: now, updatedAt: now })))
        .run();
    }
  });
}
