// The shared Discord Gateway can only be managed by administrative agent keys.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { Hono } from 'hono';
import { beforeAll, expect, it, vi } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';
import { discordGatewayRouter } from './discord-gateway-api';
import type { Env } from '../types';

beforeAll(seedDatabase);

it.each([['POST', 'connect'], ['POST', 'disconnect'], ['GET', 'status']])(
  'restricts %s /discord-gateway/%s to the administrative capability', async (method, path) => {
    const fetch = vi.fn(async () => Response.json({ ok: true }));
    const get = vi.fn(() => ({ fetch }));
    const bindings = { ...env, DISCORD_GATEWAY: { idFromName: () => 'singleton', get } as unknown as DurableObjectNamespace };
    const app = new Hono<{ Bindings: Env }>().route('/discord-gateway', discordGatewayRouter);
    const request = async (headers: Record<string, string>) => {
      const ctx = createExecutionContext();
      const result = await app.request(`https://test.local/discord-gateway/${path}`, {
        method, headers, ...(method === 'POST' ? { body: '{}' } : {}),
      }, bindings, ctx);
      await waitOnExecutionContext(ctx);
      return result;
    };
    expect((await request({})).status).toBe(401);
    // Agent profile roles are editable and must not grant administrative access.
    await env.DB.prepare("UPDATE api_keys SET role = 'admin', is_admin = 0 WHERE id = ?").bind(getTestAgentId()).run();
    expect((await request(authHeaders())).status).toBe(403);
    expect(get).not.toHaveBeenCalled();
    await env.DB.prepare('UPDATE api_keys SET is_admin = 1 WHERE id = ?').bind(getTestAgentId()).run();
    try {
      expect((await request(authHeaders())).status).toBe(200);
      expect(fetch).toHaveBeenCalledOnce();
    } finally {
      await env.DB.prepare('UPDATE api_keys SET is_admin = 0, role = NULL WHERE id = ?').bind(getTestAgentId()).run();
    }
  },
);
