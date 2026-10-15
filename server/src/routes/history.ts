import type { FastifyInstance } from 'fastify';
import type { AppContext } from '../context.js';
import { productHistory, serviceHistory } from '../domain/history.js';
import { idParams, pagination, parse } from '../lib/validation.js';

/** "Who got / bought it and when" lists for a catalog service and a product (see API.md, History). */
export function historyRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;

  app.get('/services/:id/history', async (request) => {
    const { id } = parse(idParams, request.params);
    const page = parse(pagination, request.query);
    return serviceHistory(db, id, page);
  });

  app.get('/products/:id/history', async (request) => {
    const { id } = parse(idParams, request.params);
    const page = parse(pagination, request.query);
    return productHistory(db, id, page);
  });
}
