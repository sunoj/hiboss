// Shared test helpers for hiboss server integration tests.
// Exports database seeding, auth helpers, and request builders.
// Depends on cloudflare:test env and the app's auth hashing.

import { env } from 'cloudflare:test';
import { hashApiKey } from './middleware/auth';

const TEST_API_KEY = 'hb_test_key_0000000000000000';

const SCHEMA_STATEMENTS = [
  "CREATE TABLE IF NOT EXISTS api_keys (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), name TEXT NOT NULL, key_hash TEXT NOT NULL UNIQUE, callback_url TEXT, default_priority TEXT NOT NULL DEFAULT 'normal' CHECK (default_priority IN ('critical', 'high', 'normal', 'low')), rate_limit INTEGER, created_at TEXT NOT NULL DEFAULT (datetime('now')), last_used_at TEXT)",
  "CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), agent_id TEXT NOT NULL, direction TEXT NOT NULL CHECK (direction IN ('agent_to_boss', 'boss_to_agent')), mode TEXT NOT NULL CHECK (mode IN ('async', 'blocking')), channel TEXT CHECK (channel IN ('discord', 'telegram', 'email')), body TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'read', 'replied')), reply_to TEXT REFERENCES messages(id), priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('critical', 'high', 'normal', 'low')), metadata TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')), FOREIGN KEY (agent_id) REFERENCES api_keys(id))",
  "CREATE TABLE IF NOT EXISTS channel_configs (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), agent_id TEXT NOT NULL, channel TEXT NOT NULL CHECK (channel IN ('discord', 'telegram', 'email')), config TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL DEFAULT (datetime('now')), FOREIGN KEY (agent_id) REFERENCES api_keys(id), UNIQUE(agent_id, channel))",
  'CREATE INDEX IF NOT EXISTS idx_messages_agent ON messages(agent_id, created_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(agent_id, direction, status)',
  'CREATE INDEX IF NOT EXISTS idx_messages_reply ON messages(reply_to)',
];

let seeded = false;

export async function seedDatabase(): Promise<void> {
  if (seeded) return;
  for (const stmt of SCHEMA_STATEMENTS) {
    await env.DB.prepare(stmt).run();
  }
  const keyHash = await hashApiKey(TEST_API_KEY);
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('test-agent-id', 'test-agent', keyHash)
    .run();
  seeded = true;
}

export function authHeaders(): Record<string, string> {
  return {
    Authorization: `Bearer ${TEST_API_KEY}`,
    'Content-Type': 'application/json',
  };
}

export function getTestAgentId(): string {
  return 'test-agent-id';
}
