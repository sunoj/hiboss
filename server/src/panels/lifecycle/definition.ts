// Prepares atomic definition replacement against the current producer checkpoint.
// Exports prepareDefinition; replacement installs a validated new baseline and fences leases.
// Dependencies: publication validators and durable lifecycle operation contracts.

import { bodyHash, isJsonValue, isRecord, validatePublication } from '../definition/helpers';
import type { PendingControl } from './control';
import type { PanelRecord } from './repository';
import { DEFAULT_TTL_SECONDS, deriveExpiresAt, PanelFault, terminal, type Checkpoint, type Lifecycle } from './types';

export async function prepareDefinition(row: PanelRecord, snapshot: Checkpoint, agentId: string, key: string, value: unknown, epoch: string | null): Promise<PendingControl> {
  if (!isRecord(value) || value.protocolVersion !== 2) throw new PanelFault('unsupported_protocol', 400);
  const allowed = ['protocolVersion', 'expectedMetadataVersion', 'expectedDefinitionRevision', 'expectedEpoch', 'expectedState', 'catalogId', 'catalogVersion', 'spec', 'stateSchema', 'initialState', 'summary'];
  if (Object.keys(value).some(k => !allowed.includes(k))) throw new PanelFault('invalid_command', 422);
  const lifecycle = { ...JSON.parse(row.lifecycle_json) as Lifecycle, lastObservedAt: null };
  if (terminal(lifecycle.taskState)) throw new PanelFault('panel_ended');
  if (value.expectedMetadataVersion !== row.metadata_version || value.expectedDefinitionRevision !== row.definition_revision) throw new PanelFault('revision_conflict');
  if (value.expectedEpoch !== epoch) throw new PanelFault('fenced_epoch');
  if (!isRecord(value.expectedState) || value.expectedState.epoch !== snapshot.epoch || value.expectedState.sequence !== snapshot.sequence) throw new PanelFault('state_conflict');
  const validation = validatePublication(value);
  if (!validation.ok || !isRecord(value.initialState) || !isJsonValue(value.initialState.task)) throw new PanelFault('invalid_spec', 422);
  const now = new Date().toISOString();
  return { operationId: crypto.randomUUID(), panelId: row.panel_id, agentId, key, hash: await bodyHash(value), expectedVersion: row.metadata_version,
    definitionRevision: row.definition_revision, lifecycle, createdAt: now,
    snapshot: { ...snapshot, definitionRevision: row.definition_revision + 1, epoch: null, sequence: 0, task: value.initialState.task,
      observationVersion: 0, lastObservedAt: null, staleAt: null, expiresAt: deriveExpiresAt(row.created_at, null, lifecycle.ttlSeconds ?? DEFAULT_TTL_SECONDS), leaseExpiresAt: null, persistedAt: Date.now() },
    definition: { catalogId: String(value.catalogId), catalogVersion: Number(value.catalogVersion), spec: JSON.stringify(value.spec), schema: JSON.stringify(value.stateSchema), initial: JSON.stringify(value.initialState), summary: JSON.stringify(value.summary ?? {}) },
  };
}
