import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import {
  CATALOG_SECTIONS,
  createCategory,
  deleteCategory,
  listCategories,
  mergeCategory,
  orderCategories,
  renameCategory,
  scopeFor,
  SERVICE_CATEGORIES,
} from '../domain/categories.js';
import { idParams, parse, requiredText } from '../lib/validation.js';

const id = z.number().int().positive();
const section = z.enum(CATALOG_SECTIONS);
const listQuery = z.object({ section: section.optional() });
const createBody = z.object({ section, serviceCategory: z.enum(SERVICE_CATEGORIES).nullish(), name: requiredText(100) });
const renameBody = z.object({ name: requiredText(100) });
const orderBody = z.object({ ids: z.array(id).min(1).max(500) });
const mergeBody = z.object({ intoId: id });

/** Warehouse categories (see API.md, Catalog categories). */
export function categoryRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;

  app.get('/catalog/categories', async (request) => {
    const q = parse(listQuery, request.query);
    return { items: listCategories(db, q.section) };
  });

  app.post('/catalog/categories', async (request) => {
    const input = parse(createBody, request.body);
    return createCategory(db, scopeFor(input.section, input.serviceCategory), input.name);
  });

  app.patch('/catalog/categories/:id', async (request) => {
    const params = parse(idParams, request.params);
    const input = parse(renameBody, request.body);
    return renameCategory(db, params.id, input.name);
  });

  app.put('/catalog/categories/order', async (request) => {
    const input = parse(orderBody, request.body);
    return { items: orderCategories(db, input.ids) };
  });

  app.post('/catalog/categories/:id/merge', async (request) => {
    const params = parse(idParams, request.params);
    const input = parse(mergeBody, request.body);
    return mergeCategory(db, params.id, input.intoId);
  });

  app.delete('/catalog/categories/:id', async (request, reply) => {
    const params = parse(idParams, request.params);
    deleteCategory(db, params.id);
    return reply.code(204).send();
  });
}
