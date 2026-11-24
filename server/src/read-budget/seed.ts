// Production-shaped D1 fixture for the read-budget gate: a live working set plus history layers.
// Exports seedLiveState, seedHistoryLayer and the fixture identities; each layer adds ~16 k messages.
// Depends on cloudflare:test D1 and the shared test schema; history is always older than one day.

import { env } from 'cloudflare:test';
import { createAgentAuth, seedBossToken } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

// One layer has the production shape at half size: two busy agents, a long tail.
const VOLUMES = [5_000, 4_500, 2_000, 1_500, 1_000, 750, 500, 300, 200, 100, 75, 40, 20, 10, 4, 1];
export const AGENTS = VOLUMES.map((_, index) => `rb-agent-${String(index).padStart(2, '0')}`);
export const AGENT_KEYS = AGENTS.map((id) => `hb_read_budget_${id}`);
export const BOSS_ID = 'rb-boss';
export const BOSS_TOKEN = 'hb_boss_read_budget_admin_0000001';
export const SESSIONS = 200;
export const STREAM_SESSION = 'rb-session-1';
export const PENDING_ASK = 'rb-pending-blocking';
export const WEBHOOK_PATH = '/api/webhooks/1234567890123456789/rb-webhook-token';
const LAYER_MESSAGES = VOLUMES.reduce((sum, volume) => sum + volume, 0);

/** Agents, boss, sessions, and the small current working set the polls should be sized by. */
export async function seedLiveState(): Promise<void> {
  for (const [index, id] of AGENTS.entries()) await createAgentAuth(id, AGENT_KEYS[index]);
  await seedBossToken('Read Budget Boss', 'admin', BOSS_TOKEN, BOSS_ID);
  await env.DB.prepare(`WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x + 1 FROM n WHERE x < ?)
    INSERT INTO sessions (id, agent_id, label, branch) SELECT 'rb-session-' || x, ?, 'rb/' || x, 'main' FROM n`)
    .bind(SESSIONS - 1, AGENTS[0]).run();
  const hourAgo = new Date(Date.now() - 3_600_000).toISOString();
  const later = new Date(Date.now() + 7_200_000).toISOString();
  for (let index = 0; index < 6; index += 1) {
    const id = index === 0 ? PENDING_ASK : `rb-pending-${index}`;
    await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status,
      session_id, metadata, created_at, expires_at) VALUES (?, ?, 'agent_to_boss', ?, 'api', 'Ask', 'sent',
      ?, ?, ?, ?)`).bind(id, AGENTS[index * 2], index % 2 === 0 ? 'blocking' : 'async', STREAM_SESSION,
      index % 2 === 0 ? null : '{"options":["Go"]}', hourAgo, index < 3 ? later : null).run();
  }
  await seedPanels('rb-live', 3, hourAgo, 'running', 'open');
  await seedWebhook();
}

/** One integration with a live webhook URL, as created by POST /api/integrations. */
async function seedWebhook(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO api_keys (id, name, kind, rate_limit) VALUES ('rb-webhook', 'Read Budget Hook',
      'integration', 30)`),
    env.DB.prepare(`INSERT INTO sessions (id, agent_id, label, status) VALUES ('rb-webhook-session', 'rb-webhook',
      'webhook-rb', 'idle')`),
    env.DB.prepare(`INSERT INTO agent_webhooks (id, agent_id, session_id, token_hash, label, created_by_agent_id)
      VALUES ('1234567890123456789', 'rb-webhook', 'rb-webhook-session', ?, 'Read Budget Hook', ?)`)
      .bind(await hashApiKey('rb-webhook-token'), AGENTS[0]),
  ]);
}

/** Appends one history layer (`layer` 0, 1, …), each older than the previous one. */
export async function seedHistoryLayer(layer: number): Promise<void> {
  const base = `datetime('2026-01-01', '-${layer * 400} days')`;
  let offset = layer * LAYER_MESSAGES;
  for (const [index, volume] of VOLUMES.entries()) {
    await seedMessages(AGENTS[index], AGENTS[(index + 1) % AGENTS.length], offset, volume, base);
    offset += volume;
  }
  await env.DB.prepare(`WITH RECURSIVE n(x) AS (VALUES(?) UNION ALL SELECT x + 1 FROM n WHERE x < ?)
    INSERT INTO session_events (session_id, sequence, kind, payload, created_at)
    SELECT 'rb-session-' || (x % ?), x, 'message', '{}', ${base} FROM n`)
    .bind(layer * 8_000, layer * 8_000 + 7_999, SESSIONS).run();
  const created = await env.DB.prepare(`SELECT ${base} AS at`).first<{ at: string }>();
  await seedPanels(`rb-h${layer}`, 150, created?.at ?? '2025-01-01 00:00:00', 'completed', 'accepted');
}

async function seedMessages(agent: string, peer: string, offset: number, volume: number, base: string): Promise<void> {
  // 1 in 10 is a decision with a passed deadline; 3 in 10 address the next agent; a few stay unread.
  await env.DB.prepare(`WITH RECURSIVE n(x) AS (VALUES(?) UNION ALL SELECT x + 1 FROM n WHERE x < ?)
    INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, target_agent_id,
      session_id, metadata, created_at, updated_at, expires_at)
    SELECT 'rb-m-' || x, ?,
      CASE WHEN x % 10 < 5 THEN 'agent_to_boss' WHEN x % 10 < 8 THEN 'boss_to_agent' ELSE 'agent_to_agent' END,
      CASE WHEN x % 30 = 1 THEN 'blocking' ELSE 'async' END, 'api', 'history ' || x,
      CASE WHEN x % 10 = 0 THEN 'replied' WHEN x % 97 = 6 THEN 'sent' WHEN x % 10 < 2 THEN 'replied' ELSE 'read' END,
      CASE WHEN x % 10 >= 8 THEN ? END, 'rb-session-' || (x % ${SESSIONS}),
      CASE WHEN x % 10 = 0 THEN '{"options":["Yes","No"]}' END,
      datetime(${base}, '+' || ((x % 20000) * 800) || ' seconds'),
      datetime(${base}, '+' || ((x % 20000) * 800) || ' seconds'),
      CASE WHEN x % 10 = 0 THEN datetime(${base}, '+' || ((x % 20000) * 800 + 3600) || ' seconds') END
    FROM n`).bind(offset, offset + volume - 1, agent, peer).run();
}

async function seedPanels(prefix: string, count: number, createdAt: string, taskState: string, state: string): Promise<void> {
  const lifecycle = JSON.stringify({ taskState, mode: 'run', expectedUpdateIntervalSeconds: 15, ttlSeconds: 3600 });
  await env.DB.prepare(`WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x + 1 FROM n WHERE x < ?)
    INSERT INTO panels (panel_id, agent_id, target_boss_id, task_key, session_id, title, catalog_id,
      catalog_version, summary_json, idempotency_key, request_hash, created_at, lifecycle_json)
    SELECT ? || '-p-' || x, ?, ?, 'task-' || x, ?, 'Panel ' || x, 'progress', 1, '{}', ? || '-k-' || x, 'h',
      strftime('%Y-%m-%dT%H:%M:%fZ', ?, '+' || x || ' minutes'), ? FROM n`)
    .bind(count - 1, prefix, AGENTS[0], BOSS_ID, STREAM_SESSION, prefix, createdAt, lifecycle).run();
  await env.DB.prepare(`INSERT INTO interaction_requests (request_id, panel_id, revision, state, blocking,
      idempotency_key, request_hash, created_at)
    SELECT panel_id || '-r', panel_id, 1, ?, 0, 'k', 'h', created_at FROM panels WHERE panel_id LIKE ? || '-p-%'`)
    .bind(state, prefix).run();
  await env.DB.prepare(`INSERT INTO interaction_revisions (request_id, revision, definition_json)
    SELECT request_id, 1, '{"title":"Intake"}' FROM interaction_requests WHERE request_id LIKE ? || '-p-%'`)
    .bind(prefix).run();
}
