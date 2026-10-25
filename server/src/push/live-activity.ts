// Ends an ask's Live Activities over APNs (direct mode) and purges stale activity tokens.
// Exports endContentState, endLiveActivities and purgeLiveActivityTokens; depends on D1 and apns.
// The content state matches the app's DecisionActivityAttributes.ContentState and the shared
// fixture docs/fixtures/live-activity-end-state.json. Never logs activity tokens.
import { sendApnsRequest, type ApnsEnvironment } from '../apns';
import type { Env, MessageRow, Priority } from '../types';
import type { Resolution } from './relay';
import { liveDeviceSql } from './devices';

const END_TIMEOUT_MS = 5_000;
/** Rows older than this are purged by the scheduled job; no ask stays open that long. */
export const LIVE_ACTIVITY_TOKEN_TTL_HOURS = 48;

/** How the ask closed, as the app's DecisionCompletion; null for an expiry without an answer. */
export type EndCompletion = { kind: 'answeredElsewhere' | 'autoSelected'; answer: string | null } | null;

export interface EndContentState {
  body: string;
  options: string[];
  priority: Priority;
  completion?: Record<string, { _0?: string }>;
}

/** The end state shows no ask text; optional fields are omitted, never null. */
export function endContentState(priority: Priority, completion: EndCompletion): EndContentState {
  const state: EndContentState = { body: '', options: [], priority };
  if (completion) {
    state.completion = { [completion.kind]: completion.answer === null ? {} : { _0: completion.answer } };
  }
  return state;
}

interface ActivityTokenRow {
  boss_id: string;
  activity_token: string;
  environment: ApnsEnvironment;
  bundle_id: string;
}

async function completionFor(env: Env, resolution: Resolution): Promise<EndCompletion> {
  if (resolution.status === 'expired') return null;
  const reply = await env.DB.prepare(`SELECT body, metadata FROM messages
    WHERE reply_to = ? AND direction = 'boss_to_agent' ORDER BY created_at LIMIT 1`)
    .bind(resolution.id).first<{ body: string; metadata: string | null }>();
  let auto = false;
  try {
    auto = !!reply?.metadata && (JSON.parse(reply.metadata) as Record<string, unknown>).auto_default === true;
  } catch {
    auto = false;
  }
  return { kind: auto ? 'autoSelected' : 'answeredElsewhere', answer: reply?.body ?? null };
}

/**
 * Sends `end` to the ask's activity tokens on devices of `audienceBossIds` (the bosses who can read
 * the ask now), then deletes every token row of the ask. Other rows are deleted without a push.
 */
export async function endLiveActivities(env: Env, message: Pick<MessageRow, 'id' | 'priority'>,
  status: Resolution['status'], audienceBossIds: ReadonlySet<string>): Promise<void> {
  const stored = (await env.DB.prepare(`SELECT d.boss_id, t.activity_token, t.environment, d.bundle_id
    FROM live_activity_tokens t JOIN boss_devices d ON d.id = t.device_id
    WHERE t.message_id = ? AND ${liveDeviceSql('d')}`)
    .bind(message.id).all<ActivityTokenRow>()).results ?? [];
  if (stored.length === 0) return;
  const rows = stored.filter((row) => audienceBossIds.has(row.boss_id));
  const now = Math.floor(Date.now() / 1000);
  const state = endContentState(message.priority, await completionFor(env, { id: message.id, status }));
  const body = JSON.stringify({ aps: { timestamp: now, event: 'end', 'dismissal-date': now,
    'content-state': state } });
  for (const row of rows) {
    try {
      await sendApnsRequest(env, { token: row.activity_token, environment: row.environment,
        topic: `${row.bundle_id}.push-type.liveactivity`, pushType: 'liveactivity', priority: '10',
        body, signal: AbortSignal.timeout(END_TIMEOUT_MS) });
    } catch {
      // Best effort per activity: the app also ends activities whose ask is closed on launch.
    }
  }
  await env.DB.prepare('DELETE FROM live_activity_tokens WHERE message_id = ?').bind(message.id).run();
}

/** Scheduled purge; a failure is reported and never blocks the sweeps after it. */
export async function purgeLiveActivityTokens(env: Env): Promise<void> {
  try {
    await env.DB.prepare(`DELETE FROM live_activity_tokens
      WHERE updated_at < datetime('now', '-${LIVE_ACTIVITY_TOKEN_TTL_HOURS} hours')`).run();
  } catch {
    console.error('Failed to purge Live Activity tokens');
  }
}
