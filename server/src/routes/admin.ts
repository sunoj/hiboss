// Admin routes for creating API keys and managing channel configs.
// Exports POST /api/keys, GET /api/channels, GET /api/channels/stats, and PUT /api/channels/:channel.
// Depends on Hono, auth middleware, hashing helpers, and shared types.

import { Hono } from 'hono';
import type { Channel, ChannelConfigRow, Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';
import { agentAdmin } from '../middleware/agent-admin';
import { createAgent } from '../agent-keys';
import { logAudit } from '../audit';
import { getChannelStatsResponse } from './admin-channel-stats';

const router = new Hono<{ Bindings: Env }>({});
router.use('*', apiAuth);
router.use('*', agentAdmin);

router.post('/keys', async (c) => {
  const payload = await c.req.json<Record<string, unknown>>();
  const name = typeof payload.name === 'string' ? payload.name.trim() : '';
  if (!name) {
    return c.text('name is required', 400);
  }
  const inserted = await createAgent(c.env.DB, name, { type: 'agent', id: getAgentId(c) });
  if (!inserted) {
    return c.text('agent name already exists', 409);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', getAgentId(c), 'key.create', 'api_key', inserted.id, name));
  return c.json(inserted, 201);
});

router.get('/keys', async (c) => {
  const rows = await c.env.DB
    .prepare('SELECT id, name, created_at, last_used_at FROM api_keys ORDER BY created_at DESC')
    .all<{ id: string; name: string; created_at: string; last_used_at: string | null }>();
  return c.json({
    keys: rows.results ?? [],
  });
});

router.get('/channels', async (c) => {
  const agentId = getAgentId(c);
  const rows = await c.env.DB
    .prepare('SELECT id, channel, config, enabled, created_at FROM channel_configs WHERE agent_id = ?')
    .bind(agentId)
    .all<ChannelConfigRow>();
  const channels = (rows.results ?? []).map((row) => ({
    id: row.id,
    channel: row.channel,
    config: safeParse(row.config),
    enabled: row.enabled === 1,
    created_at: row.created_at,
  }));
  return c.json({ channels });
});

router.get('/channels/stats', async (c) => {
  const agentId = getAgentId(c);
  const verbose = c.req.query('verbose') === '1' || c.req.query('verbose') === 'true';
  return c.json(await getChannelStatsResponse(c.env, agentId, verbose));
});

router.put('/channels/:channel', async (c) => {
  const agentId = getAgentId(c);
  const channel = normalizeChannel(c.req.param('channel'));
  if (!channel) {
    return c.text('invalid channel', 400);
  }
  const payload = await c.req.json<unknown>();
  if (!isPlainObject(payload)) {
    return c.text('config must be an object', 400);
  }
  const configJson = JSON.stringify(payload);
  const row = await c.env.DB
    .prepare(
      'INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, ?, ?, 1) ON CONFLICT(agent_id, channel) DO UPDATE SET config = excluded.config, enabled = 1 RETURNING id, channel, config, enabled, created_at'
    )
    .bind(agentId, channel, configJson)
    .first<ChannelConfigRow>();
  if (!row) {
    return c.text('failed to save configuration', 500);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'channel.set', 'channel_config', row.id, channel));
  return c.json({
    id: row.id,
    channel: row.channel,
    config: safeParse(row.config),
    enabled: row.enabled === 1,
    created_at: row.created_at,
  });
});

export const adminRouter = router;

function normalizeChannel(value: string | null): Channel | null {
  if (value === 'discord' || value === 'telegram' || value === 'email') {
    return value;
  }
  return null;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function safeParse(value: string): Record<string, unknown> {
  try {
    return JSON.parse(value) as Record<string, unknown>;
  } catch {
    return {};
  }
}
