// Panel publication parsing, cursors, hashing, and response shaping.
// Exports request validation helpers and panel response builders.
// Dependencies: Hono, panel-runtime, and local panel types.

import type { Context } from 'hono';
import {
  validateAnswerSchema,
  validateAnswers,
  validateCatalogIdentity,
  validatePanelPublication,
  type ValidationIssue,
} from '@hiboss/panel-runtime';
import type { Env } from '../../types';
import type { JsonValue, PanelDefinition, PanelDefinitionRow, PanelMetadata, PanelMetadataRow } from './types';

export type PanelRequest = Record<string, unknown>;
export type PanelErrorCode = 'invalid_spec' | 'unsupported_catalog' | 'idempotency_conflict' | 'invalid_cursor' | 'not_found';
export type PanelStatus = 400 | 403 | 404 | 409 | 422 | 500;
export type PanelContext = Context<{ Bindings: Env }>;

interface Cursor {
  readonly createdAt: string;
  readonly panelId: string;
}

interface CursorResult {
  readonly ok: true;
  readonly value: Cursor;
}

interface CursorFailure {
  readonly ok: false;
  readonly message: string;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function stringField(payload: PanelRequest, key: string): string | null {
  const value = payload[key];
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

export function isJsonValue(value: unknown): value is JsonValue {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return true;
  if (typeof value === 'number') return Number.isFinite(value);
  if (Array.isArray(value)) return value.every(isJsonValue);
  return isRecord(value) && Object.values(value).every(isJsonValue);
}

export function canonicalJson(value: unknown): string {
  if (value === null || typeof value === 'string' || typeof value === 'boolean' || typeof value === 'number') {
    const encoded = JSON.stringify(value);
    if (encoded === undefined) throw new Error('request body contains a non-JSON value');
    return encoded;
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (!isRecord(value)) throw new Error('request body contains a non-JSON value');
  const entries = Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`);
  return `{${entries.join(',')}}`;
}

export async function bodyHash(value: unknown): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonicalJson(value)));
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

export function encodeCursor(cursor: Cursor): string {
  return btoa(JSON.stringify(cursor)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

export function decodeCursor(value: string | undefined): CursorResult | CursorFailure {
  if (value === undefined) return { ok: true, value: { createdAt: '', panelId: '' } };
  try {
    const decoded = JSON.parse(atob(value.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - (value.length % 4)) % 4))) as unknown;
    if (!isRecord(decoded) || typeof decoded.createdAt !== 'string' || typeof decoded.panelId !== 'string' || !decoded.createdAt || !decoded.panelId) {
      return { ok: false, message: 'Cursor is malformed' };
    }
    return { ok: true, value: { createdAt: decoded.createdAt, panelId: decoded.panelId } };
  } catch {
    return { ok: false, message: 'Cursor is malformed' };
  }
}

export function validationError(issue: ValidationIssue, pathPrefix = ''): { code: PanelErrorCode; message: string; path: string } {
  return { code: issue.code === 'unsupported_catalog' ? 'unsupported_catalog' : 'invalid_spec', message: issue.message, path: `${pathPrefix}${issue.path}` };
}

export function validatePublication(payload: PanelRequest): { ok: true } | { ok: false; error: ReturnType<typeof validationError> } {
  const catalog = validateCatalogIdentity(payload.catalogId, payload.catalogVersion);
  if (!catalog.ok) return { ok: false, error: validationError(catalog.error) };
  const schema = validateAnswerSchema(payload.stateSchema);
  if (!schema.ok) return { ok: false, error: validationError(schema.error, '/stateSchema') };
  const publication = validatePanelPublication(payload);
  if (!publication.ok) return { ok: false, error: validationError(publication.error) };
  const initialState = validateAnswers(schema.value, payload.initialState);
  if (!initialState.ok) return { ok: false, error: validationError(initialState.error, '/initialState') };
  return { ok: true };
}

export function metadataFromRow(row: PanelMetadataRow): PanelMetadata {
  return {
    panelId: row.panel_id,
    agentId: row.agent_id,
    agentName: row.agent_name,
    targetBossId: row.target_boss_id,
    taskKey: row.task_key,
    sessionId: row.session_id,
    sessionLabel: row.session_label,
    title: row.title,
    catalogId: row.catalog_id,
    catalogVersion: row.catalog_version,
    definitionRevision: row.definition_revision,
    metadataVersion: row.metadata_version,
    summary: JSON.parse(row.summary_json) as JsonValue,
    createdAt: row.created_at,
  };
}

export function definitionFromRow(row: PanelDefinitionRow): PanelDefinition {
  return {
    definitionRevision: row.definition_revision,
    protocolVersion: row.protocol_version,
    catalogId: row.catalog_id,
    catalogVersion: row.catalog_version,
    spec: JSON.parse(row.spec_json) as JsonValue,
    stateSchema: JSON.parse(row.state_schema_json) as JsonValue,
    initialState: JSON.parse(row.initial_state_json) as JsonValue,
    createdAt: row.created_at,
  };
}

export function errorResponse(
  c: PanelContext,
  status: PanelStatus,
  code: PanelErrorCode,
  message: string,
  path?: string,
): Response {
  const error = { code, message, retryable: false, ...(path === undefined ? {} : { path, fieldErrors: [{ path, message }] }) };
  return c.json({ error }, status);
}
