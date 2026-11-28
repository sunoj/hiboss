// Registry of every repeated D1 read path with its per-call rows-read budget and its driver.
// Exports READ_PATHS; a call is one idle poll (loops), one request (endpoints) or one run (cron).
// Depends on the drivers, the production-shaped seed identities, and the scheduled entry points.

import { env } from 'cloudflare:test';
import { handleScheduled } from '../scheduled';
import { accessDigest } from '../routes/session-list';
import { repairPanelRooms } from '../panels/lifecycle/repair';
import type { Env } from '../types';
import { driveRequest, driveStream, driveTask, type Measurement } from './drive';
import { AGENT_KEYS, BOSS_TOKEN, PENDING_ASK, STREAM_SESSION, WEBHOOK_PATH } from './seed';

export interface ReadPath {
  id: string;
  kind: 'loop' | 'endpoint' | 'cron';
  /** Max rows read per call. */
  budget: number;
  /** Loops only: max rows read while connecting, through the first poll. */
  connectBudget?: number;
  /** Endpoints only: max D1 statements per request, so a per-row lookup (N+1) fails the gate. */
  statementBudget?: number;
  /** Growth with history is allowed only up to `ceiling` rows per call at the 2N fixture. */
  exemption?: { ceiling: number; reason: string };
  /** The production `d1 insights` statement this path issues, for the watch script's report. */
  insight: string;
  measure: () => Promise<Measurement>;
}

const POLLS = 5;
const boss = { Authorization: `Bearer ${BOSS_TOKEN}` };
const agent = (index: number) => ({ Authorization: `Bearer ${AGENT_KEYS[index]}` });
const get = (path: string, headers: Record<string, string>) => () =>
  new Request(`http://localhost${path}`, { headers });
const stream = (path: string, headers: Record<string, string>) => () => driveStream(get(path, headers), POLLS);
const roomStub = {
  idFromName: (name: string) => name,
  get: () => ({ fetch: async () => new Response(null, { status: 204 }) }),
};

export const READ_PATHS: ReadPath[] = [
  { id: 'agent-stream', kind: 'loop', budget: 20, connectBudget: 30,
    insight: 'agent SSE poll (messages.created_at >= ? AND agent/target branches)',
    measure: stream('/api/messages/stream', agent(1)) },
  { id: 'agent-session-stream', kind: 'loop', budget: 20, connectBudget: 30,
    insight: 'agent SSE poll, session-scoped variant',
    measure: stream(`/api/messages/stream?session=${STREAM_SESSION}`, agent(0)) },
  { id: 'agent-reply-long-poll', kind: 'loop', budget: 20, connectBudget: 30,
    insight: 'POST /api/messages/:id/poll (message by id + replies by reply_to)',
    measure: () => driveStream(() => new Request(`http://localhost/api/messages/${PENDING_ASK}/poll?timeout=60`,
      { method: 'POST', headers: agent(0) }), POLLS) },
  { id: 'boss-message-stream', kind: 'loop', budget: 100, connectBudget: 300,
    insight: 'boss SSE poll (agent_to_boss sent since cursor)',
    measure: stream('/api/boss/stream', boss) },
  { id: 'boss-option-stream', kind: 'loop', budget: 100, connectBudget: 300,
    insight: 'option stream active options (agent_id IN … AND expires_at > ?) and recent resolutions',
    measure: stream('/api/boss/stream?options=true', boss) },
  { id: 'boss-feed-stream', kind: 'loop', budget: 150, connectBudget: 300,
    insight: 'feed poll (rowid IN agent branch UNION ALL target branch, updated_at >= ?)',
    measure: stream('/api/boss/stream?feed=true', boss) },
  { id: 'boss-required-input-stream', kind: 'loop', budget: 150, connectBudget: 400,
    insight: 'pending-input scan on connect, then changed + tracked rows per poll',
    measure: stream('/api/boss/stream?inputs=true', boss) },
  { id: 'session-event-stream', kind: 'loop', budget: 20, connectBudget: 60,
    insight: 'session_events MIN(sequence) + events after cursor',
    measure: stream(`/api/sessions/${STREAM_SESSION}/stream?after=999999999`, boss) },
  { id: 'panels-list', kind: 'endpoint', budget: 300, statementBudget: 6,
    insight: 'GET /api/panels (panels JOIN api_keys LEFT JOIN sessions/panel_preferences ORDER BY created_at DESC)',
    measure: () => driveRequest(get('/api/panels?limit=50', boss)) },
  { id: 'message-detail-by-prefix', kind: 'endpoint', budget: 100,
    insight: 'GET /api/boss/messages/:id (messages.id range seek for a full id or a prefix)',
    measure: () => driveRequest(get('/api/boss/messages/rb-m-5', boss)) },
  { id: 'sessions-delta', kind: 'endpoint', budget: 100, statementBudget: 8,
    insight: 'GET /api/boss/sessions?include_inactive=true&updated_after= (idx_sessions_agent_updated + removals)',
    measure: async () => {
      const agents = await env.DB.prepare('SELECT id FROM api_keys').all<{ id: string }>();
      const cursor = `${new Date().toISOString().slice(0, 19).replace('T', ' ')}~${
        await accessDigest(agents.results.map(row => row.id))}`;
      return driveRequest(get(`/api/boss/sessions?include_inactive=true&updated_after=${encodeURIComponent(cursor)}`, boss));
    } },
  // Externally driven: a misconfigured CI loop can make it hot, so its reads and statements are capped.
  { id: 'discord-webhook-post', kind: 'endpoint', budget: 40, statementBudget: 14,
    insight: 'POST /api/webhooks/:id/:token (agent_webhooks by id, rate window upsert, app-only send)',
    measure: () => driveRequest(() => new Request(`http://localhost${WEBHOOK_PATH}`, { method: 'POST',
      headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ content: 'Read budget probe' }) })) },
  { id: 'interaction-requests', kind: 'endpoint', budget: 100,
    insight: 'GET /api/interaction-requests (open questionnaires for the boss)',
    measure: () => driveRequest(get('/api/interaction-requests', boss)) },
  { id: 'cron-every-5-min', kind: 'cron', budget: 100,
    insight: 'scheduled: expiry sweep, app-only delivery queue, pairing/sign-in cleanup, panel repair',
    measure: () => driveTask(async (env: Env) => {
      await handleScheduled(env, 30);
      await repairPanelRooms({ ...env, PANEL_ROOM: roomStub } as unknown as Env);
    }) },
  { id: 'cron-hourly', kind: 'cron', budget: 25_000,
    exemption: { ceiling: 25_000, reason: 'The abandoned-ask sweep runs 24 times a day and visits every open '
      + 'agent_to_boss row without a deadline; read rows stay open, and the ask predicate is JSON, so no plain '
      + 'index narrows it. ~19 k rows per run at 32 k messages ≈ 0.5 M rows/day.' },
    insight: 'scheduled first five minutes of the hour: adds the abandoned-ask sweep',
    measure: () => driveTask((env: Env) => handleScheduled(env, 2)) },
];
