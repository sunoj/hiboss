// Registry of every repeated D1 read path with its per-call rows-read budget and its driver.
// Exports READ_PATHS; a call is one idle poll (loops), one request (endpoints) or one run (cron).
// Depends on the drivers, the production-shaped seed identities, and the scheduled entry points.

import { handleScheduled } from '../scheduled';
import { repairPanelRooms } from '../panels/lifecycle/repair';
import type { Env } from '../types';
import { driveRequest, driveStream, driveTask, type Measurement } from './drive';
import { AGENT_KEYS, BOSS_TOKEN, PENDING_ASK, STREAM_SESSION } from './seed';

export interface ReadPath {
  id: string;
  kind: 'loop' | 'endpoint' | 'cron';
  /** Max rows read per call. */
  budget: number;
  /** Loops only: max rows read while connecting, through the first poll. */
  connectBudget?: number;
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
  { id: 'panels-list', kind: 'endpoint', budget: 300,
    insight: 'GET /api/panels (panels JOIN api_keys LEFT JOIN sessions ORDER BY created_at DESC LIMIT)',
    measure: () => driveRequest(get('/api/panels?limit=50', boss)) },
  { id: 'interaction-requests', kind: 'endpoint', budget: 100,
    insight: 'GET /api/interaction-requests (open questionnaires for the boss)',
    measure: () => driveRequest(get('/api/interaction-requests', boss)) },
  { id: 'cron-every-5-min', kind: 'cron', budget: 100,
    insight: 'scheduled: expiry sweep, delivery queue, pairing/sign-in cleanup, panel repair',
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
