// Agent/boss panel publication and read routes.
// Exports panelsRouter for metadata, immutable definitions, and scoped cursors.
// Dependencies: Hono, D1, auth middleware, and panel-runtime helpers.

import { publicationLifecycle, readPreference } from '../lifecycle/repository';
import { faultResponse, type Lifecycle } from '../lifecycle/types';
import { Hono } from 'hono';
import { dualAuth, getAgentId, getBossId, isBossAuth } from '../../middleware/auth';
import type { Env } from '../../types';
import {
  bodyHash,
  decodeCursor,
  definitionFromRow,
  encodeCursor,
  errorResponse,
  isJsonValue,
  isRecord,
  metadataFromRow,
  stringField,
  validatePublication,
  type PanelContext,
  type PanelRequest,
} from './helpers';
import type { JsonValue, PanelDefinitionRow, PanelMetadataRow } from './types';

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', dualAuth);

function requiredBodyFields(payload: PanelRequest): { ok: true } | { ok: false; path: string; message: string } {
  if (payload.protocolVersion !== 2) return { ok: false, path: '/protocolVersion', message: 'protocolVersion must be 2' };
  for (const key of ['taskKey', 'sessionId', 'title', 'catalogId'] as const) {
    if (stringField(payload, key) === null) return { ok: false, path: `/${key}`, message: `${key} is required` };
  }
  if (!Number.isInteger(payload.catalogVersion)) return { ok: false, path: '/catalogVersion', message: 'catalogVersion must be an integer' };
  if (!isRecord(payload.spec)) return { ok: false, path: '/spec', message: 'spec is required' };
  if (!isRecord(payload.stateSchema)) return { ok: false, path: '/stateSchema', message: 'stateSchema is required' };
  if (!('initialState' in payload) || !isJsonValue(payload.initialState)) return { ok: false, path: '/initialState', message: 'initialState is required' };
  if (payload.summary !== undefined && (!isRecord(payload.summary) || !isJsonValue(payload.summary))) return { ok: false, path: '/summary', message: 'summary must be a JSON object' };
  return { ok: true };
}

async function requestPayload(c: PanelContext): Promise<PanelRequest> {
  const body = await c.req.json<unknown>();
  return isRecord(body) ? body : {};
}

async function findByKey(c: PanelContext, agentId: string, key: string): Promise<PanelMetadataRow | null> {
  return c.env.DB.prepare('SELECT p.panel_id, p.agent_id, k.name AS agent_name, p.target_boss_id, p.task_key, p.session_id, s.label AS session_label, p.title, p.catalog_id, p.catalog_version, p.definition_revision, p.metadata_version, p.summary_json, p.request_hash, p.created_at, p.lifecycle_json, p.final_snapshot_json, p.supersedes_panel_id FROM panels p JOIN api_keys k ON k.id = p.agent_id LEFT JOIN sessions s ON s.id = p.session_id WHERE p.agent_id = ? AND p.idempotency_key = ?')
    .bind(agentId, key).first<PanelMetadataRow>();
}

async function hasPublicationScope(c: PanelContext, agentId: string, bossId: string, sessionId: string): Promise<boolean> {
  const row = await c.env.DB.prepare(
    'SELECT 1 AS allowed FROM sessions s JOIN boss_agent_access ba ON ba.agent_id = s.agent_id WHERE s.id = ? AND s.agent_id = ? AND ba.boss_id = ? LIMIT 1',
  ).bind(sessionId, agentId, bossId).first<{ allowed: number }>();
  return row !== null;
}

async function resolveBoss(c: PanelContext, agentId: string): Promise<string | null> {
  const rows = await c.env.DB.prepare('SELECT boss_id FROM boss_agent_access WHERE agent_id = ? ORDER BY boss_id LIMIT 2').bind(agentId).all<{ boss_id: string }>();
  return rows.results?.length === 1 ? rows.results[0]?.boss_id ?? null : null;
}

function publicationResponse(row: PanelMetadataRow): { panelId: string; definitionRevision: number; metadataVersion: number; catalogVersion: number; createdAt: string } {
  return {
    panelId: row.panel_id,
    definitionRevision: row.definition_revision,
    metadataVersion: row.metadata_version,
    catalogVersion: row.catalog_version,
    createdAt: row.created_at,
  };
}

routes.post('/', async (c) => {
  if (isBossAuth(c)) return errorResponse(c, 403, 'not_found', 'Agent authentication required');
  const idempotencyKey = c.req.header('Idempotency-Key')?.trim();
  if (!idempotencyKey) return errorResponse(c, 400, 'invalid_spec', 'Idempotency-Key header is required');
  let payload: PanelRequest;
  try {
    payload = await requestPayload(c);
  } catch {
    return errorResponse(c, 400, 'invalid_spec', 'Request body must be valid JSON');
  }
  const agentId = getAgentId(c);
  const hash = await bodyHash(payload);
  const existing = await findByKey(c, agentId, idempotencyKey);
  if (existing) return existing.request_hash === hash
    ? c.json(publicationResponse(existing), 201)
    : errorResponse(c, 409, 'idempotency_conflict', 'Idempotency-Key was already used with a different body');
  const fields = requiredBodyFields(payload);
  if (!fields.ok) return errorResponse(c, 400, 'invalid_spec', fields.message, fields.path);
  const validation = validatePublication(payload);
  if (!validation.ok) return errorResponse(c, validation.error.code === 'unsupported_catalog' ? 400 : 422, validation.error.code, validation.error.message, validation.error.path);
  const targetBossId = stringField(payload, 'targetBossId') ?? await resolveBoss(c, agentId);
  const sessionId = stringField(payload, 'sessionId');
  if (targetBossId === null) return errorResponse(c, 400, 'invalid_spec', 'targetBossId is required', '/targetBossId');
  if (sessionId === null) return errorResponse(c, 400, 'invalid_spec', 'sessionId is required', '/sessionId');
  if (!await hasPublicationScope(c, agentId, targetBossId, sessionId)) return errorResponse(c, 404, 'not_found', 'Publication target was not found');
  let lifecycle: Lifecycle;
  try { lifecycle = publicationLifecycle(payload.lifecycle); } catch (error) { return faultResponse(error); }
  if (payload.supersedesPanelId !== undefined) {
    if (typeof payload.supersedesPanelId !== 'string') return errorResponse(c, 422, 'invalid_spec', 'Invalid predecessor');
    const predecessor = await visiblePanel(c, payload.supersedesPanelId);
    if (!predecessor || predecessor.target_boss_id !== targetBossId || !['completed', 'failed', 'cancelled'].includes(JSON.parse(predecessor.lifecycle_json).taskState)) return errorResponse(c, 422, 'invalid_spec', 'Predecessor must be an ended panel for the same boss');
  }
  return persistPublication(c, payload, agentId, idempotencyKey, hash, targetBossId, sessionId, lifecycle);
});

async function persistPublication(c: PanelContext, payload: PanelRequest, agentId: string, idempotencyKey: string,
  hash: string, targetBossId: string, sessionId: string, lifecycle: Lifecycle): Promise<Response> {
  const now = new Date().toISOString();
  const panelId = `panel_${crypto.randomUUID()}`;
  const metadata = {
    panelId,
    agentId,
    targetBossId,
    taskKey: stringField(payload, 'taskKey') as string,
    sessionId,
    title: stringField(payload, 'title') as string,
    catalogId: stringField(payload, 'catalogId') as string,
    catalogVersion: payload.catalogVersion as number,
    definitionRevision: 1,
    metadataVersion: 1,
    summary: (payload.summary ?? {}) as JsonValue,
    createdAt: now,
  };
  try {
    await c.env.DB.batch([
      c.env.DB.prepare('INSERT INTO panels (panel_id, agent_id, target_boss_id, task_key, session_id, title, catalog_id, catalog_version, definition_revision, metadata_version, summary_json, idempotency_key, request_hash, created_at, lifecycle_json, supersedes_panel_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
        .bind(panelId, agentId, targetBossId, metadata.taskKey, sessionId, metadata.title, metadata.catalogId, metadata.catalogVersion, 1, 1, JSON.stringify(metadata.summary), idempotencyKey, hash, now, JSON.stringify(lifecycle), payload.supersedesPanelId ?? null),
      c.env.DB.prepare('INSERT INTO panel_definitions (panel_id, definition_revision, protocol_version, catalog_id, catalog_version, spec_json, state_schema_json, initial_state_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
        .bind(panelId, 1, 2, metadata.catalogId, metadata.catalogVersion, JSON.stringify(payload.spec), JSON.stringify(payload.stateSchema), JSON.stringify(payload.initialState), now),
    ]);
  } catch {
    const raced = await findByKey(c, agentId, idempotencyKey);
    if (raced) return raced.request_hash === hash
      ? c.json(publicationResponse(raced), 201)
      : errorResponse(c, 409, 'idempotency_conflict', 'Idempotency-Key was already used with a different body');
    return errorResponse(c, 500, 'not_found', 'Panel could not be persisted');
  }
  return c.json({ panelId, definitionRevision: 1, metadataVersion: 1, catalogVersion: metadata.catalogVersion, createdAt: now }, 201);
}

routes.get('/', async (c) => {
  const cursor = decodeCursor(c.req.query('cursor'));
  if (!cursor.ok) return errorResponse(c, 400, 'invalid_cursor', cursor.message);
  const rawLimit = Number(c.req.query('limit') ?? '50');
  const limit = Number.isInteger(rawLimit) && rawLimit > 0 ? Math.min(rawLimit, 100) : 50;
  const bossRequest = isBossAuth(c);
  const identity = bossRequest ? getBossId(c) : getAgentId(c);
  const scope = bossRequest
    ? 'p.target_boss_id = ? AND EXISTS (SELECT 1 FROM boss_agent_access ba WHERE ba.boss_id = ? AND ba.agent_id = p.agent_id)'
    : 'p.agent_id = ?';
  const binds: (string | number)[] = bossRequest ? [identity, identity] : [identity];
  const cursorClause = cursor.value.panelId ? ' AND (p.created_at < ? OR (p.created_at = ? AND p.panel_id < ?))' : '';
  if (cursor.value.panelId) binds.push(cursor.value.createdAt, cursor.value.createdAt, cursor.value.panelId);
  binds.push(limit + 1);
  const rows = await c.env.DB.prepare(`SELECT p.panel_id, p.agent_id, k.name AS agent_name, p.target_boss_id, p.task_key, p.session_id, s.label AS session_label, p.title, p.catalog_id, p.catalog_version, p.definition_revision, p.metadata_version, p.summary_json, p.request_hash, p.created_at, p.lifecycle_json, p.final_snapshot_json, p.supersedes_panel_id FROM panels p JOIN api_keys k ON k.id = p.agent_id LEFT JOIN sessions s ON s.id = p.session_id WHERE ${scope}${cursorClause} ORDER BY p.created_at DESC, p.panel_id DESC LIMIT ?`)
    .bind(...binds).all<PanelMetadataRow>();
  const results = rows.results ?? [];
  const page = results.slice(0, limit);
  const last = page.at(-1);
  return c.json({ panels: await Promise.all(page.map(async row => ({ ...metadataFromRow(row), preference: await readPreference(c.env.DB, row.panel_id, row.target_boss_id) }))), nextCursor: results.length > limit && last ? encodeCursor({ createdAt: last.created_at, panelId: last.panel_id }) : null });
});

async function visiblePanel(c: PanelContext, panelId: string): Promise<PanelMetadataRow | null> {
  if (isBossAuth(c)) return c.env.DB.prepare('SELECT p.panel_id, p.agent_id, k.name AS agent_name, p.target_boss_id, p.task_key, p.session_id, s.label AS session_label, p.title, p.catalog_id, p.catalog_version, p.definition_revision, p.metadata_version, p.summary_json, p.request_hash, p.created_at, p.lifecycle_json, p.final_snapshot_json, p.supersedes_panel_id FROM panels p JOIN api_keys k ON k.id = p.agent_id LEFT JOIN sessions s ON s.id = p.session_id WHERE p.panel_id = ? AND p.target_boss_id = ? AND EXISTS (SELECT 1 FROM boss_agent_access ba WHERE ba.boss_id = ? AND ba.agent_id = p.agent_id)')
    .bind(panelId, getBossId(c), getBossId(c)).first<PanelMetadataRow>();
  return c.env.DB.prepare('SELECT p.panel_id, p.agent_id, k.name AS agent_name, p.target_boss_id, p.task_key, p.session_id, s.label AS session_label, p.title, p.catalog_id, p.catalog_version, p.definition_revision, p.metadata_version, p.summary_json, p.request_hash, p.created_at, p.lifecycle_json, p.final_snapshot_json, p.supersedes_panel_id FROM panels p JOIN api_keys k ON k.id = p.agent_id LEFT JOIN sessions s ON s.id = p.session_id WHERE p.panel_id = ? AND p.agent_id = ?')
    .bind(panelId, getAgentId(c)).first<PanelMetadataRow>();
}

routes.get('/:id', async (c) => {
  const metadata = await visiblePanel(c, c.req.param('id'));
  if (!metadata) return errorResponse(c, 404, 'not_found', 'Panel was not found');
  const definition = await c.env.DB.prepare('SELECT panel_id, definition_revision, protocol_version, catalog_id, catalog_version, spec_json, state_schema_json, initial_state_json, created_at FROM panel_definitions WHERE panel_id = ? AND definition_revision = ?')
    .bind(metadata.panel_id, metadata.definition_revision).first<PanelDefinitionRow>();
  if (!definition) return errorResponse(c, 404, 'not_found', 'Panel was not found');
  return c.json({ ...metadataFromRow(metadata), preference: await readPreference(c.env.DB, metadata.panel_id, metadata.target_boss_id), definition: definitionFromRow(definition) });
});

export const panelsRouter = routes;
