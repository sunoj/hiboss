// Authenticated lifecycle record reads and durable operation receipt lookup.
// Exports record, checkpoint, preference, and publication policy helpers.
// Dependencies: D1, definition validation, and lifecycle contracts.

import { bossCanAccessAgent } from '../access';
import { validateAnswers, validateAnswerSchema } from '@hiboss/panel-runtime';
import { isRecord, isJsonValue } from '../definition/helpers';
import type { JsonValue } from '../definition/types';
import { defaultLifecycle, defaultPreference, DEFAULT_TTL_SECONDS, MAX_TTL_SECONDS, MIN_TTL_SECONDS, PanelFault, type Lifecycle, type Preference, type Checkpoint, type PanelId } from './types';

export interface PanelRecord {
  panel_id: PanelId; agent_id: string; target_boss_id: string; definition_revision: number; metadata_version: number;
  lifecycle_json: string; final_snapshot_json: string | null; initial_state_json: string; state_schema_json: string; created_at: string;
}
export async function readRecord(db: D1Database, panelId: string): Promise<PanelRecord> {
  const row = await db.prepare('SELECT p.*, d.initial_state_json, d.state_schema_json FROM panels p JOIN panel_definitions d ON d.panel_id = p.panel_id AND d.definition_revision = p.definition_revision WHERE p.panel_id = ?').bind(panelId).first<PanelRecord>();
  if (!row) throw new PanelFault('not_found', 404);
  return row;
}
export async function authorize(db: D1Database, row: PanelRecord, identity: string, role: 'producer' | 'subscriber'): Promise<void> {
  const agent = role === 'producer' ? identity : row.agent_id;
  const boss = role === 'producer' ? row.target_boss_id : identity;
  if (agent !== row.agent_id) throw new PanelFault('not_found', 404);
  if (boss !== row.target_boss_id) {
    const admin = await db.prepare("SELECT 1 FROM bosses WHERE id = ? AND role = 'admin'").bind(boss).first();
    if (!admin) throw new PanelFault('not_found', 404);
  }
  const access = await bossCanAccessAgent(db, boss, agent);
  if (!access) throw new PanelFault('not_found', 404);
}
export function initialCheckpoint(row: PanelRecord): Checkpoint {
  const root = JSON.parse(row.initial_state_json) as Record<string, JsonValue>;
  const lifecycle = JSON.parse(row.lifecycle_json) as Lifecycle;
  if (!lifecycle.expiresAt) throw new PanelFault('invalid_lifecycle', 422);
  return { protocolVersion: 2, serverTime: Date.now(), panelId: row.panel_id, definitionRevision: row.definition_revision, epoch: null, sequence: 0,
    task: root.task, observationVersion: 0, lastObservedAt: null, staleAt: null, expiresAt: lifecycle.expiresAt, leaseExpiresAt: null, persistedAt: 0 };
}
export function validateTask(row: PanelRecord, task: unknown): asserts task is JsonValue {
  const schema = validateAnswerSchema(JSON.parse(row.state_schema_json));
  if (!isJsonValue(task) || JSON.stringify(task).length > 49_152 || !schema.ok || !validateAnswers(schema.value, { task }).ok) throw new PanelFault('invalid_state', 422);
}
export function publicationLifecycle(value: unknown): Lifecycle {
  if (value === undefined) return defaultLifecycle();
  if (!isRecord(value) || Object.keys(value).some(k => !['mode', 'expectedUpdateIntervalSeconds', 'ttlSeconds'].includes(k))) throw new PanelFault('invalid_lifecycle', 422);
  const mode = value.mode ?? 'run';
  const interval = value.expectedUpdateIntervalSeconds ?? 15;
  const ttlSeconds = value.ttlSeconds ?? DEFAULT_TTL_SECONDS;
  if (!['run', 'monitor'].includes(String(mode)) || typeof interval !== 'number' || !Number.isInteger(interval) || interval < 5 || interval > 3600
    || typeof ttlSeconds !== 'number' || !Number.isInteger(ttlSeconds) || ttlSeconds < MIN_TTL_SECONDS || ttlSeconds > MAX_TTL_SECONDS) throw new PanelFault('invalid_lifecycle', 422);
  return { ...defaultLifecycle(), mode: mode as Lifecycle['mode'], expectedUpdateIntervalSeconds: interval, ttlSeconds };
}
export async function readPreference(db: D1Database, panelId: string, bossId: string): Promise<Preference> {
  const row = await db.prepare('SELECT value_json FROM panel_preferences WHERE panel_id = ? AND boss_id = ?').bind(panelId, bossId).first<{ value_json: string }>();
  return row ? JSON.parse(row.value_json) as Preference : defaultPreference();
}
export async function operationReceipt(db: D1Database, panelId: string, agentId: string, key: string, hash: string): Promise<unknown | null> {
  const row = await db.prepare('SELECT request_hash, receipt_json FROM panel_operations WHERE panel_id = ? AND agent_id = ? AND idempotency_key = ?').bind(panelId, agentId, key).first<{ request_hash: string; receipt_json: string }>();
  if (!row) return null;
  if (row.request_hash !== hash) throw new PanelFault('idempotency_conflict');
  return JSON.parse(row.receipt_json) as unknown;
}
