// Panel publication storage and wire types.
// Exports typed JSON, rows, metadata, and definition contracts.
// Dependencies: panel-runtime validation types.

import type { AnswerSchema, PanelSpec } from '@hiboss/panel-runtime';

export type JsonValue = null | boolean | number | string | JsonValue[] | { readonly [key: string]: JsonValue };

export interface PanelMetadataRow {
  readonly panel_id: string;
  readonly agent_id: string;
  readonly target_boss_id: string;
  readonly task_key: string;
  readonly session_id: string;
  readonly title: string;
  readonly catalog_id: string;
  readonly catalog_version: number;
  readonly definition_revision: number;
  readonly metadata_version: number;
  readonly summary_json: string;
  readonly request_hash: string;
  readonly created_at: string;
}

export interface PanelDefinitionRow {
  readonly panel_id: string;
  readonly definition_revision: number;
  readonly protocol_version: number;
  readonly catalog_id: string;
  readonly catalog_version: number;
  readonly spec_json: string;
  readonly state_schema_json: string;
  readonly initial_state_json: string;
  readonly created_at: string;
}

export interface PanelMetadata {
  readonly panelId: string;
  readonly agentId: string;
  readonly targetBossId: string;
  readonly taskKey: string;
  readonly sessionId: string;
  readonly title: string;
  readonly catalogId: string;
  readonly catalogVersion: number;
  readonly definitionRevision: number;
  readonly metadataVersion: number;
  readonly summary: JsonValue;
  readonly createdAt: string;
}

export interface PanelDefinition {
  readonly definitionRevision: number;
  readonly protocolVersion: number;
  readonly catalogId: string;
  readonly catalogVersion: number;
  readonly spec: PanelSpec | JsonValue;
  readonly stateSchema: AnswerSchema | JsonValue;
  readonly initialState: JsonValue;
  readonly createdAt: string;
}
