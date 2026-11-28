// Independent D1 fixtures for message query and session-state scenarios.
// Exports seeded identities, the typed worker environment and seedMessageQueries.
// Depends on Cloudflare test bindings and the shared database schema fixture.

import { env } from 'cloudflare:test';
import type { D1PreparedStatement } from '@cloudflare/workers-types';
import type { Env, MessageRow } from '../../types';
import { getTestAgentId, seedDatabase } from '../../test-helpers';

export const testEnv = env as Env;
export const agentId = getTestAgentId();
export const rateAgentId = 'message-query-rate-agent';
export const msgId = 'fetch-msg-test-001';
export const parentId = 'reply-parent-001';
export const sessId = 'infer-sess-001';

function message(id: string, body: string, fields: Partial<MessageRow> = {}): D1PreparedStatement {
  const row = {
    id,
    agent_id: agentId,
    direction: 'agent_to_boss',
    mode: 'async',
    body,
    status: 'sent',
    priority: 'normal',
    ...fields,
  };
  const columns = Object.keys(row);
  const placeholders = columns.map(() => '?').join(', ');
  return env.DB.prepare(`INSERT INTO messages (${columns.join(', ')}) VALUES (${placeholders})`)
    .bind(...Object.values(row));
}

export async function seedMessageQueries(): Promise<void> {
  await seedDatabase();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(rateAgentId, 'rate-agent', 'message-query-fixture-hash').run();
  await env.DB.batch([
    message(msgId, 'fetch test body'),
    message(parentId, 'parent msg', { direction: 'boss_to_agent' }),
    message('reply-child-001', 'reply 1', {
      reply_to: parentId, metadata: '{"answer":"Yes"}', created_at: '2026-01-01T00:00:01Z',
    }),
    message('reply-child-002', 'reply 2', { reply_to: parentId, created_at: '2026-01-01T00:00:02Z' }),
    message('idemp-msg-001', 'idempotent msg', { idempotency_key: 'idemp-key-abc' }),
    message('rate-old', 'old', { agent_id: rateAgentId, created_at: '2026-01-01T00:00:00Z' }),
    message('rate-inbound', 'incoming', { agent_id: rateAgentId, direction: 'boss_to_agent' }),
    ...Array.from({ length: 3 }, (_, index) =>
      message(`rate-msg-${index}`, 'rate test', { agent_id: rateAgentId })),
  ]);
  await env.DB.prepare("INSERT INTO sessions (id, agent_id, status) VALUES (?, ?, 'working')")
    .bind(sessId, agentId).run();
}
