// Reads request heads, immutable revisions, and recoverable answer delivery records.
// Exports scoped request queries and response builders; no writes or synthetic answers.
// Dependencies: D1, panel access checks, and request domain contracts.

import { panelTargetAccessSql } from '../access';
import { authorize, readRecord } from '../lifecycle/repository';
import { PanelFault } from '../lifecycle/types';
import type { Questionnaire, RequestRow, SubmissionRow } from './types';

export async function requestRow(db: D1Database, id: string, identity: string, role: 'producer' | 'subscriber'): Promise<RequestRow> {
  const row = await db.prepare('SELECT * FROM interaction_requests WHERE request_id = ?').bind(id).first<RequestRow>();
  if (!row) throw new PanelFault('not_found', 404);
  await authorize(db, await readRecord(db, row.panel_id), identity, role);
  return row;
}
export async function definition(db: D1Database, row: RequestRow, revision = row.revision): Promise<Questionnaire> {
  const result = await db.prepare('SELECT definition_json FROM interaction_revisions WHERE request_id = ? AND revision = ?').bind(row.request_id, revision).first<{ definition_json: string }>();
  if (!result) throw new PanelFault('not_found', 404);
  return JSON.parse(result.definition_json) as Questionnaire;
}
export function requireOpen(row: RequestRow, revision = row.revision): void {
  if (row.state !== 'open') throw new PanelFault('request_resolved');
  if (row.revision !== revision) throw new PanelFault('revision_conflict');
  if (row.expires_at && Date.parse(row.expires_at) <= Date.now()) throw new PanelFault('request_expired');
}
export async function submissionRow(db: D1Database, id: string): Promise<SubmissionRow | null> {
  return db.prepare('SELECT s.*, d.acknowledged_at FROM interaction_submissions s JOIN interaction_deliveries d USING (submission_id) WHERE s.submission_id = ?').bind(id).first<SubmissionRow>();
}
export function submissionResponse(row: SubmissionRow): Record<string, unknown> {
  return { submissionId: row.submission_id, requestId: row.request_id, requestRevision: row.revision, bossId: row.boss_id,
    answers: JSON.parse(row.answers_json) as unknown, provenance: JSON.parse(row.provenance_json) as unknown,
    acceptedAt: row.accepted_at, delivery: row.acknowledged_at ? 'delivered' : 'pending' };
}
export async function requestResponse(db: D1Database, row: RequestRow, revision = row.revision): Promise<Record<string, unknown>> {
  const submitted = row.submission_id ? await submissionRow(db, row.submission_id) : null;
  return { requestId: row.request_id, panelId: row.panel_id, requestRevision: row.revision, definitionRevision: revision,
    state: row.state === 'open' && row.expires_at && Date.parse(row.expires_at) <= Date.now() ? 'expired' : row.state,
    expiresAt: row.expires_at, withdrawalReason: row.withdrawal_reason, createdAt: row.created_at,
    definition: await definition(db, row, revision), submission: submitted ? submissionResponse(submitted) : null };
}

// Every mutation rechecks current panel access and task state inside its D1 statement.
export const ACTIVE_PANEL = `SELECT 1 FROM panels p WHERE p.panel_id = interaction_requests.panel_id
  AND json_extract(p.lifecycle_json, '$.taskState') IN ('running', 'paused')
  AND ${panelTargetAccessSql('p')}`;
