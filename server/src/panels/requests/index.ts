// Authenticated HTTP surface for durable panel questionnaires and answer receipts.
// Exports panelRequestsRouter and interactionRequestsRouter for the Worker entry point.
// Dependencies: Hono auth, D1 request transactions, schema validation, and signatures.

import { Hono } from 'hono';
import { dualAuth, getAgentId, getBossId, getBossName, getBossRole, getBossTokenId, isBossAuth } from '../../middleware/auth';
import type { Env } from '../../types';
import { isRecord, type PanelContext } from '../definition/helpers';
import { authorize, readRecord } from '../lifecycle/repository';
import { faultResponse, PanelFault } from '../lifecycle/types';
import { publishRequest, replaceRequest, withdrawRequest } from './mutations';
import { requestResponse, requestRow, submissionResponse, submissionRow } from './repository';
import { submitAnswer } from './submissions';
import { pendingRequests } from './discovery';
import type { RequestRow } from './types';
import { parseQuestionnaire, parseSubmission } from './validation';

export const panelRequestsRouter = new Hono<{ Bindings: Env }>();
export const interactionRequestsRouter = new Hono<{ Bindings: Env }>();
panelRequestsRouter.use('/:id/requests', dualAuth);
interactionRequestsRouter.use('*', dualAuth);
const identity = (c: PanelContext): string => isBossAuth(c) ? getBossId(c) : getAgentId(c);
const role = (c: PanelContext): 'subscriber' | 'producer' => isBossAuth(c) ? 'subscriber' : 'producer';
function owner(c: PanelContext): string {
  if (isBossAuth(c)) throw new PanelFault('permission_denied', 403);
  return getAgentId(c);
}
const route = (handler: (c: PanelContext) => Promise<Response>) => async (c: PanelContext): Promise<Response> => {
  try { return await handler(c); } catch (error) { return faultResponse(error); }
};
async function body(c: PanelContext): Promise<Record<string, unknown>> {
  let parsed: unknown;
  try { const raw = await c.req.text(); if (new TextEncoder().encode(raw).length > 196_608) throw new Error(); parsed = JSON.parse(raw); }
  catch { throw new PanelFault('invalid_request', 400); }
  if (!isRecord(parsed)) throw new PanelFault('invalid_request', 422);
  return parsed;
}
function revision(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) < 1) throw new PanelFault('invalid_revision', 422);
  return Number(value);
}
function reason(value: unknown): string {
  if (typeof value !== 'string' || !value.trim() || value.length > 1000) throw new PanelFault('withdrawal_reason_required', 422);
  return value.trim();
}

interactionRequestsRouter.get('/', route(async c => c.json(await pendingRequests(
  c.env.DB, identity(c), role(c), c.req.query('cursor'), c.req.query('limit'),
))));

panelRequestsRouter.post('/:id/requests', route(async c => {
  const agent = owner(c);
  const result = await publishRequest(c.env.DB, c.req.param('id')!, agent, c.req.header('Idempotency-Key') ?? '', parseQuestionnaire(await body(c)));
  return c.json(result, 201);
}));
panelRequestsRouter.get('/:id/requests', route(async c => {
  const panelId = c.req.param('id')!;
  await authorize(c.env.DB, await readRecord(c.env.DB, panelId), identity(c), role(c));
  const rows = await c.env.DB.prepare('SELECT * FROM interaction_requests WHERE panel_id = ? ORDER BY created_at, request_id').bind(panelId).all<RequestRow>();
  const requests = await Promise.all(rows.results.map(row => requestResponse(c.env.DB, row)));
  const needsInput = rows.results.some(row => row.blocking === 1 && row.state === 'open' && (!row.expires_at || Date.parse(row.expires_at) > Date.now()));
  return c.json({ requests, needsInput });
}));
interactionRequestsRouter.get('/:id', route(async c => {
  const row = await requestRow(c.env.DB, c.req.param('id')!, identity(c), role(c));
  const requested = c.req.query('revision');
  return c.json(await requestResponse(c.env.DB, row, requested === undefined ? row.revision : revision(Number(requested))));
}));
interactionRequestsRouter.put('/:id', route(async c => {
  const agent = owner(c);
  const row = await requestRow(c.env.DB, c.req.param('id')!, agent, 'producer');
  const { expectedRevision, ...form } = await body(c);
  return c.json(await replaceRequest(c.env.DB, row, agent, revision(expectedRevision), parseQuestionnaire(form)));
}));
interactionRequestsRouter.post('/:id/withdraw', route(async c => {
  const agent = owner(c);
  const row = await requestRow(c.env.DB, c.req.param('id')!, agent, 'producer');
  const input = await body(c);
  if (Object.keys(input).some(k => !['expectedRevision', 'reason'].includes(k))) throw new PanelFault('invalid_request', 422);
  await withdrawRequest(c.env.DB, row, revision(input.expectedRevision), reason(input.reason));
  return c.json(await requestResponse(c.env.DB, await requestRow(c.env.DB, row.request_id, agent, 'producer')));
}));
interactionRequestsRouter.post('/:id/submissions', route(async c => {
  if (!isBossAuth(c) || !['admin', 'manager'].includes(getBossRole(c))) throw new PanelFault('permission_denied', 403);
  const id = c.req.param('id')!, bossId = getBossId(c);
  const row = await requestRow(c.env.DB, id, bossId, 'subscriber');
  const input = await body(c);
  const result = await submitAnswer(c.env.DB, row, { bossId, bossName: getBossName(c), tokenId: getBossTokenId(c) }, parseSubmission(input, id, bossId), input.signedSubmission);
  return c.json(result, 201);
}));
interactionRequestsRouter.get('/:id/submissions/:submissionId', route(async c => {
  const row = await requestRow(c.env.DB, c.req.param('id')!, identity(c), role(c));
  const submission = await submissionRow(c.env.DB, c.req.param('submissionId')!);
  if (!submission || submission.request_id !== row.request_id) throw new PanelFault('not_found', 404);
  return c.json(submissionResponse(submission));
}));
interactionRequestsRouter.post('/:id/submissions/:submissionId/ack', route(async c => {
  const agent = owner(c);
  const row = await requestRow(c.env.DB, c.req.param('id')!, agent, 'producer');
  if (row.submission_id !== c.req.param('submissionId')) throw new PanelFault('not_found', 404);
  await c.env.DB.prepare('UPDATE interaction_deliveries SET acknowledged_at = COALESCE(acknowledged_at, ?) WHERE submission_id = ?').bind(new Date().toISOString(), row.submission_id).run();
  return c.json({ submissionId: row.submission_id, delivery: 'delivered' });
}));
