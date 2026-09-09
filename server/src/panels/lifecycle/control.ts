// Durable prepare/commit/reconcile lifecycle operations with metadata CAS.
// Exports command validation, preparation, and idempotent D1 commit.
// Dependencies: lifecycle repository, D1, and validated panel state.

import { bodyHash, isRecord } from '../definition/helpers';
import { authorize, operationReceipt, readRecord, validateTask, type PanelRecord } from './repository';
import { DEFAULT_TTL_SECONDS, deriveExpiresAt, PanelFault, terminal, type Checkpoint, type ControlCommand, type Lifecycle } from './types';

export interface PendingControl {
  definition?: { catalogId: string; catalogVersion: number; spec: string; schema: string; initial: string; summary: string };
  operationId: string; panelId: string; agentId: string; key: string; hash: string;
  expectedVersion: number; definitionRevision: number; lifecycle: Lifecycle; snapshot: Checkpoint; createdAt: string;
}
export function parseControl(value: unknown): ControlCommand {
  if (!isRecord(value) || value.protocolVersion !== 2) throw new PanelFault('unsupported_protocol', 400);
  const keys = ['protocolVersion', 'action', 'expectedMetadataVersion', 'expectedDefinitionRevision', 'expectedEpoch', 'expectedState', 'openRequests', 'finalTask', 'result', 'dismissal'];
  if (Object.keys(value).some(k => !keys.includes(k))) throw new PanelFault('invalid_command', 422);
  if (!['pause', 'resume', 'complete', 'fail', 'cancel'].includes(String(value.action))) throw new PanelFault('invalid_command', 422);
  for (const key of ['expectedMetadataVersion', 'expectedDefinitionRevision']) {
    if (!Number.isInteger(value[key]) || Number(value[key]) < 1) throw new PanelFault('invalid_command', 422);
  }
  if (value.expectedEpoch !== null && typeof value.expectedEpoch !== 'string') throw new PanelFault('invalid_command', 422);
  if (value.expectedState !== null && (!isRecord(value.expectedState) || !Number.isInteger(value.expectedState.sequence)
    || Number(value.expectedState.sequence) < 0 || (value.expectedState.epoch !== null && typeof value.expectedState.epoch !== 'string'))) throw new PanelFault('invalid_command', 422);
  if (value.openRequests !== 'reject') throw new PanelFault('unsupported_request_policy', 422);
  if (value.result !== undefined && (!isRecord(value.result) || typeof value.result.title !== 'string' || !value.result.title.trim()
    || value.result.title.length > 240 || Object.keys(value.result).some(k => !['title', 'message', 'code'].includes(k) || typeof (value.result as Record<string, unknown>)[k] !== 'string'))) throw new PanelFault('invalid_result', 422);
  if (['fail', 'cancel'].includes(String(value.action)) && !value.result) throw new PanelFault('result_required', 422);
  if (value.action === 'fail' && (!isRecord(value.result) || !value.result.code)) throw new PanelFault('failure_code_required', 422);
  if (value.dismissal !== undefined) {
    const dismissal = value.dismissal;
    if (!isRecord(dismissal) || !['default', 'immediate', 'after', 'manual'].includes(String(dismissal.policy))
      || Object.keys(dismissal).some(k => !['policy', 'afterSeconds'].includes(k))
      || (dismissal.policy === 'after' ? !Number.isInteger(dismissal.afterSeconds) || Number(dismissal.afterSeconds) < 0 || Number(dismissal.afterSeconds) > 86400 : dismissal.afterSeconds !== undefined)) throw new PanelFault('invalid_dismissal', 422);
  }
  if (value.action === 'fail' && isRecord(value.dismissal) && !['default', 'manual'].includes(String(value.dismissal.policy))) throw new PanelFault('failure_requires_manual_dismissal', 422);
  return value as unknown as ControlCommand;
}
export async function prepareControl(row: PanelRecord, snapshot: Checkpoint, agentId: string, key: string, command: ControlCommand, epoch: string | null): Promise<PendingControl> {
  const lifecycle = JSON.parse(row.lifecycle_json) as Lifecycle;
  if (terminal(lifecycle.taskState)) throw new PanelFault('panel_ended');
  if (row.metadata_version !== command.expectedMetadataVersion || row.definition_revision !== command.expectedDefinitionRevision) throw new PanelFault('revision_conflict');
  if (epoch !== command.expectedEpoch) throw new PanelFault('fenced_epoch');
  if ((command.action === 'pause' && lifecycle.taskState !== 'running') || (command.action === 'resume' && lifecycle.taskState !== 'paused')) throw new PanelFault('invalid_transition');
  const isTerminal = ['complete', 'fail', 'cancel'].includes(command.action);
  if (isTerminal && (command.expectedState === null ? snapshot.epoch !== null : command.expectedState.epoch !== snapshot.epoch || command.expectedState.sequence !== snapshot.sequence)) throw new PanelFault('state_conflict');
  if (!isTerminal && (command.finalTask !== undefined || command.result !== undefined || command.dismissal !== undefined)) throw new PanelFault('invalid_command', 422);
  const task = command.finalTask === undefined ? snapshot.task : command.finalTask;
  validateTask(row, task);
  const now = new Date().toISOString();
  const states = { pause: 'paused', resume: 'running', complete: 'completed', fail: 'failed', cancel: 'cancelled' } as const;
  lifecycle.taskState = states[command.action];
  if (isTerminal) {
    lifecycle.terminalAt = now;
    lifecycle.dismissalPolicy = command.action === 'fail' ? 'manual' : 'after';
    lifecycle.dismissAt = command.action === 'fail' ? null : new Date(Date.parse(now) + (command.action === 'complete' ? 600_000 : 60_000)).toISOString();
    if (command.dismissal && command.dismissal.policy !== 'default') {
      lifecycle.dismissalPolicy = command.dismissal.policy;
      lifecycle.dismissAt = command.dismissal.policy === 'manual' ? null : new Date(Date.parse(now) + (command.dismissal.afterSeconds ?? 0) * 1000).toISOString();
    }
    lifecycle.result = command.result ?? { title: 'Completed' };
  }
  return { operationId: crypto.randomUUID(), panelId: row.panel_id, agentId, key, hash: await bodyHash(command), expectedVersion: row.metadata_version,
    definitionRevision: row.definition_revision, lifecycle, snapshot: { ...snapshot, task, leaseExpiresAt: null }, createdAt: now };
}
export async function commitControl(db: D1Database, pending: PendingControl): Promise<unknown> {
  const existing = await operationReceipt(db, pending.panelId, pending.agentId, pending.key, pending.hash);
  if (existing !== null) return existing;
  const row = await readRecord(db, pending.panelId);
  await authorize(db, row, pending.agentId, 'producer');
  const ttlSeconds = pending.lifecycle.ttlSeconds ?? DEFAULT_TTL_SECONDS;
  const receiptLifecycle = { ...pending.lifecycle, ttlSeconds, lastObservedAt: pending.lifecycle.lastObservedAt ?? pending.snapshot.lastObservedAt,
    expiresAt: deriveExpiresAt(row.created_at, pending.snapshot.lastObservedAt, ttlSeconds) };
  const receipt = { operationId: pending.operationId, metadataVersion: pending.expectedVersion + 1, definitionRevision: pending.snapshot.definitionRevision, lifecycle: receiptLifecycle,
    finalSnapshot: terminal(pending.lifecycle.taskState) ? pending.snapshot : null };
  const final = terminal(pending.lifecycle.taskState) ? JSON.stringify(pending.snapshot) : null;
  const guard = 'SELECT 1 FROM panels WHERE panel_id = ? AND last_operation_id = ?';
  const result = await db.batch([
    db.prepare('UPDATE panels SET lifecycle_json = ?, final_snapshot_json = ?, metadata_version = metadata_version + 1, last_operation_id = ?, definition_revision = ?, catalog_id = COALESCE(?, catalog_id), catalog_version = COALESCE(?, catalog_version), summary_json = COALESCE(?, summary_json) WHERE panel_id = ? AND metadata_version = ? AND definition_revision = ? AND agent_id = ? AND EXISTS (SELECT 1 FROM boss_agent_access ba WHERE ba.boss_id = panels.target_boss_id AND ba.agent_id = panels.agent_id)')
      .bind(JSON.stringify(pending.lifecycle), final, pending.operationId, pending.snapshot.definitionRevision, pending.definition?.catalogId ?? null, pending.definition?.catalogVersion ?? null, pending.definition?.summary ?? null, pending.panelId, pending.expectedVersion, pending.definitionRevision, pending.agentId),
    ...(pending.definition ? [db.prepare(`INSERT INTO panel_definitions SELECT ?, ?, 2, ?, ?, ?, ?, ?, ? WHERE EXISTS (${guard})`)
      .bind(pending.panelId, pending.snapshot.definitionRevision, pending.definition.catalogId, pending.definition.catalogVersion, pending.definition.spec, pending.definition.schema, pending.definition.initial, pending.createdAt, pending.panelId, pending.operationId)] : []),
    db.prepare(`INSERT INTO panel_operations SELECT ?, ?, ?, ?, ?, ? WHERE EXISTS (${guard})`).bind(pending.operationId, pending.panelId, pending.agentId, pending.key, pending.hash, JSON.stringify(receipt), pending.panelId, pending.operationId),
    db.prepare(`INSERT INTO panel_outbox SELECT ?, ?, ?, ?, NULL WHERE EXISTS (${guard})`).bind(pending.operationId, pending.panelId, pending.expectedVersion + 1, pending.createdAt, pending.panelId, pending.operationId),
  ]);
  if (result[0].meta.changes !== 1) throw new PanelFault('revision_conflict');
  return receipt;
}
