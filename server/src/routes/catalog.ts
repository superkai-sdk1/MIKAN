import { asc, eq } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import type { DbOrTx } from '../db/client.js';
import { aftercareTemplates, services } from '../db/schema.js';
import { badRequest, notFound } from '../lib/errors.js';
import { serviceOut, templateOut } from '../lib/serialize.js';
import { idParams, money, nonNull, nullableText, parse, queryBool, requiredText } from '../lib/validation.js';

const category = z.enum(['tattoo', 'piercing', 'other']);
const serviceFields = {
  name: requiredText(200),
  category,
  price: money,
  priceFrom: z.boolean(),
  durationMin: z.number().int().min(1).max(24 * 60),
  aftercareTemplateId: z.number().int().positive().nullish(),
  active: z.boolean(),
  sort: z.number().int().min(-100_000).max(100_000),
};
const serviceCreate = z.object({
  ...serviceFields,
  priceFrom: nonNull(serviceFields.priceFrom),
  description: nullableText(5000),
  active: nonNull(serviceFields.active),
  sort: nonNull(serviceFields.sort),
});
const servicePatch = z.object({
  name: nonNull(serviceFields.name),
  category: nonNull(category),
  price: nonNull(money),
  priceFrom: nonNull(serviceFields.priceFrom),
  durationMin: nonNull(serviceFields.durationMin),
  description: nullableText(5000),
  aftercareTemplateId: serviceFields.aftercareTemplateId,
  active: nonNull(serviceFields.active),
  sort: nonNull(serviceFields.sort),
});

const steps = z
  .array(z.object({ dayOffset: z.number().int().min(0).max(3650), text: requiredText(4000) }))
  .min(1)
  .max(50)
  .transform((list) => [...list].sort((a, b) => a.dayOffset - b.dayOffset));
const templateCreate = z.object({ name: requiredText(200), category, steps });
const templatePatch = z.object({ name: nonNull(requiredText(200)), category: nonNull(category), steps: nonNull(steps) });

function assertTemplate(db: DbOrTx, id: number | null | undefined) {
  if (id == null) return;
  if (!db.select({ id: aftercareTemplates.id }).from(aftercareTemplates).where(eq(aftercareTemplates.id, id)).get()) {
    throw badRequest('Памятка по уходу не найдена');
  }
}

export function catalogRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;

  app.get('/services', async (request) => {
    const q = parse(z.object({ includeInactive: queryBool }), request.query);
    const rows = db
      .select()
      .from(services)
      .where(q.includeInactive ? undefined : eq(services.active, true))
      .orderBy(asc(services.sort), asc(services.name), asc(services.id))
      .all();
    return { items: rows.map(serviceOut) };
  });

  app.post('/services', async (request) => {
    const input = parse(serviceCreate, request.body);
    assertTemplate(db, input.aftercareTemplateId);
    const now = Date.now();
    const row = db
      .insert(services)
      .values({
        name: input.name,
        category: input.category,
        price: input.price,
        priceFrom: input.priceFrom ?? false,
        durationMin: input.durationMin,
        description: input.description ?? null,
        aftercareTemplateId: input.aftercareTemplateId ?? null,
        active: input.active ?? true,
        sort: input.sort ?? 0,
        createdAt: now,
        updatedAt: now,
      })
      .returning()
      .get();
    return serviceOut(row);
  });

  app.patch('/services/:id', async (request) => {
    const { id } = parse(idParams, request.params);
    const input = parse(servicePatch, request.body);
    const current = db.select().from(services).where(eq(services.id, id)).get();
    if (!current) throw notFound('Услуга не найдена');
    assertTemplate(db, input.aftercareTemplateId);
    const row = db
      .update(services)
      .set({
        name: input.name ?? current.name,
        category: input.category ?? current.category,
        price: input.price ?? current.price,
        priceFrom: input.priceFrom ?? current.priceFrom,
        durationMin: input.durationMin ?? current.durationMin,
        description: input.description === undefined ? current.description : input.description,
        aftercareTemplateId: input.aftercareTemplateId === undefined ? current.aftercareTemplateId : input.aftercareTemplateId,
        active: input.active ?? current.active,
        sort: input.sort ?? current.sort,
        updatedAt: Date.now(),
      })
      .where(eq(services.id, id))
      .returning()
      .get();
    return serviceOut(row);
  });

  app.get('/aftercare-templates', async () => {
    const rows = db.select().from(aftercareTemplates).orderBy(asc(aftercareTemplates.category), asc(aftercareTemplates.name)).all();
    return { items: rows.map(templateOut) };
  });

  app.post('/aftercare-templates', async (request) => {
    const input = parse(templateCreate, request.body);
    const now = Date.now();
    const row = db
      .insert(aftercareTemplates)
      .values({ name: input.name, category: input.category, stepsJson: JSON.stringify(input.steps), createdAt: now, updatedAt: now })
      .returning()
      .get();
    return templateOut(row);
  });

  app.patch('/aftercare-templates/:id', async (request) => {
    const { id } = parse(idParams, request.params);
    const input = parse(templatePatch, request.body);
    const current = db.select().from(aftercareTemplates).where(eq(aftercareTemplates.id, id)).get();
    if (!current) throw notFound('Памятка не найдена');
    const row = db
      .update(aftercareTemplates)
      .set({
        name: input.name ?? current.name,
        category: input.category ?? current.category,
        stepsJson: input.steps ? JSON.stringify(input.steps) : current.stepsJson,
        updatedAt: Date.now(),
      })
      .where(eq(aftercareTemplates.id, id))
      .returning()
      .get();
    return templateOut(row);
  });

  app.delete('/aftercare-templates/:id', async (request, reply) => {
    const { id } = parse(idParams, request.params);
    db.transaction((tx) => {
      const current = tx.select().from(aftercareTemplates).where(eq(aftercareTemplates.id, id)).get();
      if (!current) throw notFound('Памятка не найдена');
      tx.update(services).set({ aftercareTemplateId: null, updatedAt: Date.now() }).where(eq(services.aftercareTemplateId, id)).run();
      tx.delete(aftercareTemplates).where(eq(aftercareTemplates.id, id)).run();
    });
    return reply.code(204).send();
  });
}
