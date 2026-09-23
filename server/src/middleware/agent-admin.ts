// Administrative agent capability; profile roles never confer this permission.
import type { MiddlewareHandler } from 'hono';
import type { Env } from '../types';
import { getAgentId } from './auth';

export const agentAdmin: MiddlewareHandler<{ Bindings: Env }> = async (c, next) => {
  const agent = await c.env.DB.prepare('SELECT is_admin FROM api_keys WHERE id = ?')
    .bind(getAgentId(c)).first<{ is_admin: number }>();
  if (agent?.is_admin !== 1) return c.text('admin access required', 403);
  await next();
};
