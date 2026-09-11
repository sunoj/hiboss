// Publishes, revises, and withdraws questionnaire heads with immutable history.
// Exports owner-only D1 mutations; all predicates recheck live panel access.
// Dependencies: definition hashing, request repository, and validated questionnaires.

import { bodyHash } from '../definition/helpers';
import { authorize, readRecord } from '../lifecycle/repository';
import { PanelFault } from '../lifecycle/types';
import { ACTIVE_PANEL, requireOpen, requestResponse, requestRow } from './repository';
import type { Questionnaire, RequestRow } from './types';

export async function publishRequest(db: D1Database, panelId: string, agent: string, key: string, form: Questionnaire): Promise<Record<string, unknown>> {
  if (!key || key.length > 128) throw new PanelFault('idempotency_key_required', 400);
  await authorize(db, await readRecord(db, panelId), agent, 'producer');
  const hash = await bodyHash(form);
  const prior = await publicationReceipt(db, panelId, key, hash);
  if (prior) return prior;
  if (form.expiresAt && Date.parse(form.expiresAt) <= Date.now()) throw new PanelFault('invalid_expiry', 422);
  const id = crypto.randomUUID(), now = new Date().toISOString();
  try {
    const result = await db.batch([
      db.prepare(`INSERT INTO interaction_requests (request_id, panel_id, revision, state, expires_at, blocking, idempotency_key, request_hash, created_at)
        SELECT ?, panel_id, 1, 'open', ?, ?, ?, ?, ? FROM panels WHERE panel_id = ? AND agent_id = ?
        AND json_extract(lifecycle_json, '$.taskState') IN ('running', 'paused')
        AND EXISTS (SELECT 1 FROM boss_agent_access WHERE boss_id = panels.target_boss_id AND agent_id = panels.agent_id)`)
        .bind(id, form.expiresAt ?? null, Number(form.blocking), key, hash, now, panelId, agent),
      db.prepare('INSERT INTO interaction_revisions SELECT ?, 1, ? WHERE EXISTS (SELECT 1 FROM interaction_requests WHERE request_id = ?)').bind(id, JSON.stringify(form), id),
    ]);
    if (result[0].meta.changes !== 1) throw new PanelFault('panel_ended');
  } catch (error) { const raced = await publicationReceipt(db, panelId, key, hash); if (raced) return raced; throw error; }
  return { requestId: id, requestRevision: 1 };
}
async function publicationReceipt(db: D1Database, panelId: string, key: string, hash: string): Promise<Record<string, unknown> | null> {
  const prior = await db.prepare('SELECT * FROM interaction_requests WHERE panel_id = ? AND idempotency_key = ?').bind(panelId, key).first<RequestRow>();
  if (!prior) return null;
  if (prior.request_hash !== hash) throw new PanelFault('idempotency_conflict');
  return { requestId: prior.request_id, requestRevision: 1 };
}
export async function replaceRequest(db: D1Database, row: RequestRow, agent: string, expected: number, form: Questionnaire): Promise<Record<string, unknown>> {
  requireOpen(row, expected);
  if (form.expiresAt && Date.parse(form.expiresAt) <= Date.now()) throw new PanelFault('invalid_expiry', 422);
  const result = await db.batch([
    db.prepare(`UPDATE interaction_requests SET revision = revision + 1, expires_at = ?, blocking = ? WHERE request_id = ? AND revision = ?
      AND state = 'open' AND (expires_at IS NULL OR julianday(expires_at) > julianday('now')) AND EXISTS (${ACTIVE_PANEL})`)
      .bind(form.expiresAt ?? null, Number(form.blocking), row.request_id, expected),
    db.prepare(`INSERT INTO interaction_revisions SELECT ?, ?, ? WHERE changes() = 1`).bind(row.request_id, expected + 1, JSON.stringify(form)),
  ]);
  if (result[0].meta.changes !== 1) throw new PanelFault('revision_conflict');
  return requestResponse(db, await requestRow(db, row.request_id, agent, 'producer'));
}
export async function withdrawRequest(db: D1Database, row: RequestRow, expected: number, reason: string): Promise<void> {
  if (row.state === 'withdrawn' && row.revision === expected && row.withdrawal_reason === reason) return;
  requireOpen(row, expected);
  const result = await db.prepare(`UPDATE interaction_requests SET state = 'withdrawn', withdrawal_reason = ? WHERE request_id = ? AND revision = ? AND state = 'open' AND EXISTS (${ACTIVE_PANEL})`)
    .bind(reason, row.request_id, expected).run();
  if (result.meta.changes !== 1) throw new PanelFault('request_conflict');
}
