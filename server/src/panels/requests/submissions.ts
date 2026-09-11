// Atomically accepts one typed answer with its session event and delivery receipt.
// Exports submitAnswer; retries recover the immutable original acceptance.
// Dependencies: D1 batch transactions, schema validation, and request/signature helpers.

import { validateAnswers } from '@hiboss/panel-runtime';
import { bodyHash } from '../definition/helpers';
import { PanelFault } from '../lifecycle/types';
import { ACTIVE_PANEL, definition, requireOpen, requestRow, submissionRow } from './repository';
import { authenticateSubmission, type Submitter } from './signature';
import type { RequestRow, Submission } from './types';

export async function submitAnswer(db: D1Database, row: RequestRow, actor: Submitter, input: Submission, signed: unknown): Promise<Record<string, unknown>> {
  const provenance = await authenticateSubmission(db, actor, input, signed);
  const hash = await bodyHash(input);
  const previous = await retryReceipt(db, input, hash);
  if (previous) return previous;
  requireOpen(row, input.requestRevision);
  const form = await definition(db, row);
  const validated = validateAnswers(form.answerSchema, input.answers);
  if (!validated.ok) throw new PanelFault('invalid_answers', 422, `${validated.error.path}: ${validated.error.message}`);
  const now = new Date().toISOString();
  let claimed = false;
  try { claimed = await persistAnswer(db, row, actor, input, hash, provenance, now); }
  catch (error) {
    const retried = await retryReceipt(db, input, hash);
    if (retried) return retried;
    throw error;
  }
  if (!claimed) {
    const retried = await retryReceipt(db, input, hash);
    if (retried) return retried;
    requireOpen(await requestRow(db, row.request_id, actor.bossId, 'subscriber'), input.requestRevision);
    throw new PanelFault('request_conflict');
  }
  return { submissionId: input.submissionId, requestId: row.request_id, requestRevision: input.requestRevision, acceptedAt: now, delivery: 'pending' };
}

async function retryReceipt(db: D1Database, input: Submission, hash: string): Promise<Record<string, unknown> | null> {
  const prior = await submissionRow(db, input.submissionId);
  if (!prior) return null;
  if (prior.boss_id !== input.bossId || prior.payload_hash !== hash) throw new PanelFault('idempotency_conflict');
  return { submissionId: prior.submission_id, requestId: prior.request_id, requestRevision: prior.revision, acceptedAt: prior.accepted_at, delivery: 'pending' };
}

async function persistAnswer(db: D1Database, row: RequestRow, actor: Submitter, input: Submission, hash: string, provenance: Record<string, unknown>, now: string): Promise<boolean> {
  const guard = 'SELECT 1 FROM interaction_requests WHERE request_id = ? AND submission_id = ?';
  const payload = JSON.stringify({ submissionId: input.submissionId, requestId: row.request_id, requestRevision: input.requestRevision, answers: input.answers, provenance });
  const results = await db.batch([
    db.prepare(`UPDATE interaction_requests SET state = 'accepted', submission_id = ? WHERE request_id = ? AND revision = ? AND state = 'open'
      AND (expires_at IS NULL OR julianday(expires_at) > julianday('now')) AND EXISTS (${ACTIVE_PANEL})
      AND EXISTS (SELECT 1 FROM panels p JOIN bosses b ON b.id = p.target_boss_id JOIN boss_tokens t ON t.boss_id = b.id
        WHERE p.panel_id = interaction_requests.panel_id AND b.id = ? AND b.role IN ('admin', 'manager') AND t.id = ? AND t.revoked_at IS NULL)`)
      .bind(input.submissionId, row.request_id, input.requestRevision, actor.bossId, actor.tokenId),
    db.prepare(`INSERT INTO interaction_submissions SELECT ?, ?, ?, ?, ?, ?, ?, ? WHERE EXISTS (${guard})`)
      .bind(input.submissionId, row.request_id, input.requestRevision, actor.bossId, hash, JSON.stringify(input.answers), JSON.stringify(provenance), now, row.request_id, input.submissionId),
    db.prepare(`INSERT INTO interaction_deliveries SELECT ?, NULL WHERE EXISTS (${guard})`).bind(input.submissionId, row.request_id, input.submissionId),
    db.prepare(`INSERT INTO session_events (id, session_id, sequence, kind, source, payload, created_at)
      SELECT ?, p.session_id, COALESCE((SELECT MAX(sequence) FROM session_events WHERE session_id = p.session_id), 0) + 1,
      'interaction.submitted', '{"record_type":"interaction","source_version":"v1"}', ?, ? FROM panels p WHERE p.panel_id = ? AND EXISTS (${guard})`)
      .bind(crypto.randomUUID(), payload, now, row.panel_id, row.request_id, input.submissionId),
  ]);
  return results[0].meta.changes === 1;
}
