// SELF-only entry point exposing the pre-phase-4 authentication/admin predicate.
// Delegates production routes and durable objects to the real Worker.
import worker from '../index';
import type { Env } from '../types';
import { hashApiKey } from './auth';

export { DiscordGateway, PanelRoom } from '../index';

export default {
  ...worker,
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (new URL(request.url).pathname !== '/__test/legacy-admin') {
      return worker.fetch(request, env, ctx);
    }
    const token = request.headers.get('Authorization')?.replace(/^Bearer /i, '');
    if (!token) return new Response('Unauthorized', { status: 401 });
    const agent = await env.DB.prepare('SELECT id FROM api_keys WHERE key_hash = ?')
      .bind(await hashApiKey(token)).first<{ id: string }>();
    if (!agent) return new Response('Unauthorized', { status: 401 });
    const row = await env.DB.prepare('SELECT role FROM api_keys WHERE id = ?')
      .bind(agent.id).first<{ role: string | null }>();
    return new Response(null, { status: row?.role === 'admin' ? 200 : 403 });
  },
};
