import bcrypt from 'bcryptjs';
import { eq } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { employees } from '../db/schema.js';
import { unauthorized } from '../lib/errors.js';
import { employeeOut } from '../lib/serialize.js';
import { parse } from '../lib/validation.js';

const loginBody = z.object({
  login: z.string().trim().min(1).max(100),
  password: z.string().min(1).max(200),
});

// Compared against when the login is unknown, so response time doesn't reveal valid logins.
const DUMMY_HASH = bcrypt.hashSync('timing-equalizer', 10);

export const LOGIN_RATE_LIMIT = { max: 10, timeWindow: 60_000 };

export function publicAuthRoutes(app: FastifyInstance, ctx: AppContext): void {
  app.post('/auth/login', { config: { rateLimit: LOGIN_RATE_LIMIT } }, async (request) => {
    const input = parse(loginBody, request.body);
    const employee = ctx.db
      .select()
      .from(employees)
      .where(eq(employees.login, input.login.toLowerCase()))
      .get();
    const ok = await bcrypt.compare(input.password, employee?.passwordHash ?? DUMMY_HASH);
    if (!employee || !ok) throw unauthorized('Неверный логин или пароль');
    if (!employee.active) throw unauthorized('Учётная запись отключена — обратитесь к администратору');
    const token = await request.server.jwt.sign({ sub: String(employee.id), tv: employee.tokenVersion });
    request.log.info({ employeeId: employee.id }, 'login');
    return { token, employee: employeeOut(employee) };
  });
}

export function authRoutes(app: FastifyInstance, _ctx: AppContext): void {
  app.get('/auth/me', async (request) => employeeOut(request.employee));
}
