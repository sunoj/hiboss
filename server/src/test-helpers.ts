// Shared test helpers for hiboss server integration tests.
// Exports database seeding, auth helpers, and request builders.
// Depends on cloudflare:test env and the app's auth hashing.

import { env } from 'cloudflare:test';
import { hashApiKey } from './middleware/auth';
import targetMigration from '../migrations/0041_destination_targets_external_accounts.sql?raw';
import credentialMigration from '../migrations/0042_provider_credentials.sql?raw';
import destinationMigration from '../migrations/0040_destinations.sql?raw';
import clientMigration from '../migrations/0039_boss_clients.sql?raw';
import projectSurfacesMigration from '../migrations/0044_project_surfaces.sql?raw';
import agentKeysMigration from '../migrations/0045_agent_keys.sql?raw';
import projectsMigration from '../migrations/0043_projects.sql?raw';
import postsMigration from '../migrations/0026_progress_posts.sql?raw';
import teamsMigration from '../migrations/0027_progress_teams_likes.sql?raw';
import attributionMigration from '../migrations/0029_progress_attribution.sql?raw';
import interactionMigration from '../migrations/0038_interaction_requests.sql?raw';

const TEST_API_KEY = 'hb_test_key_0000000000000000';

const SCHEMA_STATEMENTS = [
  "CREATE TABLE IF NOT EXISTS api_keys (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), name TEXT NOT NULL, key_hash TEXT NOT NULL UNIQUE, callback_url TEXT, default_priority TEXT NOT NULL DEFAULT 'normal' CHECK (default_priority IN ('critical', 'high', 'normal', 'low')), rate_limit INTEGER, channel_routing TEXT, avatar_url TEXT, role TEXT, session_info TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), last_used_at TEXT)",
  "CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), agent_id TEXT NOT NULL, direction TEXT NOT NULL CHECK (direction IN ('agent_to_boss', 'boss_to_agent', 'agent_to_agent')), mode TEXT NOT NULL CHECK (mode IN ('async', 'blocking')), channel TEXT CHECK (channel IN ('discord', 'telegram', 'email', 'api')), body TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'read', 'replied', 'expired')), reply_to TEXT REFERENCES messages(id), priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('critical', 'high', 'normal', 'low')), type TEXT DEFAULT 'text', target_agent_id TEXT, target_session_id TEXT, session_id TEXT, idempotency_key TEXT, metadata TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')), expires_at TEXT, FOREIGN KEY (agent_id) REFERENCES api_keys(id))",
  "CREATE TABLE IF NOT EXISTS delivery_queue (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), message_id TEXT NOT NULL, agent_id TEXT NOT NULL, channel TEXT NOT NULL, config TEXT NOT NULL, scheduled_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'delivered', 'failed')), error TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), FOREIGN KEY (message_id) REFERENCES messages(id))",
  "CREATE TABLE IF NOT EXISTS channel_configs (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), agent_id TEXT NOT NULL, channel TEXT NOT NULL CHECK (channel IN ('discord', 'telegram', 'email', 'api')), config TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL DEFAULT (datetime('now')), FOREIGN KEY (agent_id) REFERENCES api_keys(id), UNIQUE(agent_id, channel))",
  'CREATE INDEX IF NOT EXISTS idx_messages_agent ON messages(agent_id, created_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(agent_id, direction, status)',
  'CREATE INDEX IF NOT EXISTS idx_messages_reply ON messages(reply_to)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_idempotency ON messages(agent_id, idempotency_key) WHERE idempotency_key IS NOT NULL',
  'CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id) WHERE session_id IS NOT NULL',
  'CREATE INDEX IF NOT EXISTS idx_messages_target ON messages(target_agent_id, created_at) WHERE target_agent_id IS NOT NULL',
  'CREATE INDEX IF NOT EXISTS idx_messages_agent_expires ON messages(agent_id, expires_at) WHERE expires_at IS NOT NULL',
  'CREATE INDEX IF NOT EXISTS idx_messages_target_session ON messages(target_session_id) WHERE target_session_id IS NOT NULL',
  "CREATE INDEX IF NOT EXISTS idx_delivery_queue_pending ON delivery_queue(status, scheduled_at) WHERE status = 'pending'",
  "CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, agent_id TEXT NOT NULL, label TEXT, branch TEXT, cwd TEXT, status TEXT NOT NULL DEFAULT 'working' CHECK (status IN ('working', 'blocked', 'waiting', 'idle', 'completed')), status_text TEXT, discord_thread_id TEXT, telegram_topic_id INTEGER, started_at TEXT NOT NULL DEFAULT (datetime('now')), last_seen_at TEXT NOT NULL DEFAULT (datetime('now')), FOREIGN KEY (agent_id) REFERENCES api_keys(id))",
  'CREATE INDEX IF NOT EXISTS idx_sessions_agent ON sessions(agent_id, last_seen_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_sessions_discord_thread ON sessions(discord_thread_id) WHERE discord_thread_id IS NOT NULL',
  'CREATE INDEX IF NOT EXISTS idx_sessions_telegram_topic ON sessions(telegram_topic_id) WHERE telegram_topic_id IS NOT NULL',
  "CREATE TABLE IF NOT EXISTS session_events (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), session_id TEXT NOT NULL, sequence INTEGER NOT NULL, kind TEXT NOT NULL, direction TEXT, actor_agent_id TEXT, target_agent_id TEXT, message_id TEXT REFERENCES messages(id), source TEXT, payload TEXT, raw TEXT, created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), UNIQUE (session_id, sequence))",
  'CREATE INDEX IF NOT EXISTS idx_session_events_cursor ON session_events(session_id, sequence)',
  "CREATE TABLE IF NOT EXISTS session_events (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), session_id TEXT NOT NULL, sequence INTEGER NOT NULL, kind TEXT NOT NULL, direction TEXT, actor_agent_id TEXT, target_agent_id TEXT, message_id TEXT REFERENCES messages(id), source TEXT, payload TEXT, raw TEXT, created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), UNIQUE (session_id, sequence))",
  'CREATE INDEX IF NOT EXISTS idx_session_events_cursor ON session_events(session_id, sequence)',
  "CREATE TABLE IF NOT EXISTS routing_rules (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), owner_id TEXT NOT NULL, channel TEXT NOT NULL CHECK (channel IN ('discord', 'telegram', 'email', 'api')), pattern TEXT NOT NULL, target_agent_id TEXT NOT NULL, priority INTEGER NOT NULL DEFAULT 0, enabled INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL DEFAULT (datetime('now')), FOREIGN KEY (owner_id) REFERENCES api_keys(id), FOREIGN KEY (target_agent_id) REFERENCES api_keys(id))",
  'CREATE INDEX IF NOT EXISTS idx_routing_rules_channel ON routing_rules(channel, enabled, priority DESC)',
  "CREATE TABLE IF NOT EXISTS agent_groups (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), name TEXT NOT NULL UNIQUE, description TEXT, owner_id TEXT REFERENCES api_keys(id), created_at TEXT NOT NULL DEFAULT (datetime('now')))",
  "CREATE TABLE IF NOT EXISTS agent_group_members (group_id TEXT NOT NULL, agent_id TEXT NOT NULL, added_at TEXT NOT NULL DEFAULT (datetime('now')), PRIMARY KEY (group_id, agent_id), FOREIGN KEY (group_id) REFERENCES agent_groups(id) ON DELETE CASCADE, FOREIGN KEY (agent_id) REFERENCES api_keys(id))",
  "CREATE TABLE IF NOT EXISTS bosses (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), name TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'manager', 'viewer')), telegram_user_id TEXT, discord_user_id TEXT, agent_id TEXT REFERENCES api_keys(id), preferences TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')))",
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_telegram ON bosses(telegram_user_id) WHERE telegram_user_id IS NOT NULL',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_discord ON bosses(discord_user_id) WHERE discord_user_id IS NOT NULL',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_agent ON bosses(agent_id) WHERE agent_id IS NOT NULL',
  "CREATE TABLE IF NOT EXISTS boss_tokens (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE, label TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL DEFAULT (datetime('now')), last_used_at TEXT, revoked_at TEXT)",
  'CREATE INDEX IF NOT EXISTS idx_boss_tokens_boss ON boss_tokens(boss_id, created_at DESC)',
  "CREATE TABLE IF NOT EXISTS boss_signing_keys (id TEXT PRIMARY KEY, boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE, boss_token_id TEXT NOT NULL UNIQUE REFERENCES boss_tokens(id) ON DELETE CASCADE, algorithm TEXT NOT NULL CHECK (algorithm = 'ES256'), client_kind TEXT NOT NULL CHECK (client_kind IN ('ios', 'macos')), public_key TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')), revoked_at TEXT)",
  'CREATE INDEX IF NOT EXISTS idx_boss_signing_keys_boss ON boss_signing_keys(boss_id, created_at DESC)',
  "CREATE TABLE IF NOT EXISTS boss_pairing_codes (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE, code_hash TEXT NOT NULL UNIQUE, expires_at TEXT NOT NULL, consumed_at TEXT, redeemed_token_id TEXT REFERENCES boss_tokens(id) ON DELETE SET NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')))",
  'CREATE INDEX IF NOT EXISTS idx_boss_pairing_codes_expiry ON boss_pairing_codes(expires_at)',
  "CREATE TABLE IF NOT EXISTS boss_agent_access (boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE, agent_id TEXT NOT NULL REFERENCES api_keys(id), PRIMARY KEY (boss_id, agent_id))",
  "CREATE TABLE IF NOT EXISTS boss_devices (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE, device_token TEXT NOT NULL UNIQUE, bundle_id TEXT NOT NULL, environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')), platform TEXT NOT NULL DEFAULT 'ios' CHECK (platform = 'ios'), created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')), last_seen_at TEXT NOT NULL DEFAULT (datetime('now')))",
  'CREATE INDEX IF NOT EXISTS idx_boss_devices_boss ON boss_devices(boss_id, last_seen_at DESC)',
  "CREATE TABLE IF NOT EXISTS audit_log (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), actor_type TEXT NOT NULL CHECK (actor_type IN ('boss', 'agent', 'system')), actor_id TEXT NOT NULL, action TEXT NOT NULL, resource_type TEXT, resource_id TEXT, details TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')))",
  'CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log(actor_type, actor_id, created_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log(action, created_at DESC)',
  "CREATE TABLE IF NOT EXISTS panels (panel_id TEXT PRIMARY KEY, agent_id TEXT NOT NULL REFERENCES api_keys(id), target_boss_id TEXT NOT NULL REFERENCES bosses(id), task_key TEXT NOT NULL, session_id TEXT NOT NULL REFERENCES sessions(id), title TEXT NOT NULL, catalog_id TEXT NOT NULL, catalog_version INTEGER NOT NULL, definition_revision INTEGER NOT NULL DEFAULT 1, metadata_version INTEGER NOT NULL DEFAULT 1, summary_json TEXT NOT NULL, idempotency_key TEXT NOT NULL, request_hash TEXT NOT NULL, created_at TEXT NOT NULL, lifecycle_json TEXT NOT NULL DEFAULT '{\"taskState\":\"running\",\"mode\":\"run\",\"expectedUpdateIntervalSeconds\":15,\"ttlSeconds\":3600,\"lastObservedAt\":null,\"terminalAt\":null,\"dismissAt\":null,\"dismissalPolicy\":null,\"result\":null}', final_snapshot_json TEXT, last_operation_id TEXT, supersedes_panel_id TEXT, UNIQUE(agent_id, idempotency_key))",
  'CREATE INDEX IF NOT EXISTS idx_panels_agent_created ON panels(agent_id, created_at DESC, panel_id DESC)',
  'CREATE INDEX IF NOT EXISTS idx_panels_boss_created ON panels(target_boss_id, created_at DESC, panel_id DESC)',
  "CREATE TABLE IF NOT EXISTS panel_definitions (panel_id TEXT NOT NULL REFERENCES panels(panel_id) ON DELETE CASCADE, definition_revision INTEGER NOT NULL, protocol_version INTEGER NOT NULL, catalog_id TEXT NOT NULL, catalog_version INTEGER NOT NULL, spec_json TEXT NOT NULL, state_schema_json TEXT NOT NULL, initial_state_json TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY (panel_id, definition_revision))",
  'CREATE TABLE IF NOT EXISTS panel_preferences (   panel_id TEXT NOT NULL REFERENCES panels(panel_id) ON DELETE CASCADE,   boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,   preference_version INTEGER NOT NULL,   value_json TEXT NOT NULL,   PRIMARY KEY (panel_id, boss_id) )',
  'CREATE TABLE IF NOT EXISTS panel_operations (   operation_id TEXT PRIMARY KEY,   panel_id TEXT NOT NULL REFERENCES panels(panel_id) ON DELETE CASCADE,   agent_id TEXT NOT NULL,   idempotency_key TEXT NOT NULL,   request_hash TEXT NOT NULL,   receipt_json TEXT NOT NULL,   UNIQUE (panel_id, agent_id, idempotency_key) )',
  'CREATE TABLE IF NOT EXISTS panel_outbox (   event_id TEXT PRIMARY KEY,   panel_id TEXT NOT NULL REFERENCES panels(panel_id) ON DELETE CASCADE,   metadata_version INTEGER NOT NULL,   created_at TEXT NOT NULL,   delivered_at TEXT )',
];

let seeded = false;

export async function seedPreAgentKeysDatabase(): Promise<void> {
  for (const stmt of SCHEMA_STATEMENTS) {
    await env.DB.prepare(stmt).run();
  }
  for (const sql of interactionMigration.replace(/^--.*$/gm, '').split(';').map(value => value.trim()).filter(Boolean)) {
    await env.DB.prepare(sql.replace('CREATE TABLE ', 'CREATE TABLE IF NOT EXISTS ').replace('CREATE INDEX ', 'CREATE INDEX IF NOT EXISTS ')).run();
  }
  for (const sql of clientMigration.replace(/^--.*$/gm, '').split(';').map(value => value.trim()).filter(Boolean)) {
    await env.DB.prepare(sql).run();
  }
  for (const sql of destinationMigration.replace(/^--.*$/gm, '').split(';').map(value => value.trim()).filter(Boolean)) {
    await env.DB.prepare(sql).run();
  }
  for (const sql of targetMigration.replace(/^--.*$/gm, '').split(';').map(value => value.trim()).filter(Boolean)) {
    await env.DB.prepare(sql).run();
  }
  for (const sql of credentialMigration.replace(/^--.*$/gm, '').split(';').map(value => value.trim()).filter(Boolean)) {
    await env.DB.prepare(sql).run();
  }
  for (const migration of [postsMigration, teamsMigration, attributionMigration, projectsMigration, projectSurfacesMigration]) {
    for (const sql of migration.replace(/^--.*$/gm, '').split(';').map(value => value.trim()).filter(Boolean)) {
      await env.DB.prepare(sql).run();
    }
  }
}

export async function seedDatabase(): Promise<void> {
  if (seeded) return;
  await seedPreAgentKeysDatabase();
  const statements = agentKeysMigration.replace(/^--.*$/gm, '').split(';').map(value => value.trim()).filter(Boolean);
  await env.DB.batch(statements.map(sql => env.DB.prepare(sql)));
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

export async function seedBossToken(name: string, role: string, token: string, id?: string): Promise<string> {
  const tokenHash = await hashApiKey(token);
  const boss = id
    ? await env.DB.prepare('INSERT OR IGNORE INTO bosses (id, name, role) VALUES (?, ?, ?) RETURNING id')
      .bind(id, name, role).first<{ id: string }>()
    : await env.DB.prepare('INSERT INTO bosses (name, role) VALUES (?, ?) RETURNING id')
      .bind(name, role).first<{ id: string }>();
  if (!boss) throw new Error('failed to seed boss');
  await env.DB.prepare('INSERT OR REPLACE INTO boss_tokens (boss_id, label, token_hash) VALUES (?, ?, ?)')
    .bind(boss.id, 'test', tokenHash).run();
  return boss.id;
}
