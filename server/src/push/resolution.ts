// Resolution fan-out: after an ask closes, tells every push device of its bosses to retract it.
// Exports announceResolution, the Announce strategies (deferred, swept) and isAgentAsk.
// Depends on push transport selection and Live Activity end.
// Silent and removal-only, so quiet hours, priority and private-push preferences never suppress it.
// Best effort: every failure is swallowed and never reaches the transition that called it.
import type { Env, MessageRow } from '../types';
import { endLiveActivities } from './live-activity';
import type { Resolution } from './relay';
import { pushMode, sendDeviceResolution, type PushDevice } from './send';

export type ResolvedAsk = Pick<MessageRow,
  'id' | 'agent_id' | 'direction' | 'mode' | 'metadata' | 'priority' | 'created_at'>;

/** How a committed transition hands over its fan-out: awaited, deferred past a response, or swept. */
export type Announce = (env: Env, message: ResolvedAsk, status: Resolution['status']) => Promise<void>;

/** Most resolutions one scheduled run sends; older ones are left to the app's launch reconciliation. */
export const SWEEP_RESOLUTION_LIMIT = 50;
/** Asks fanned out at once by a sweep, within the Worker's simultaneous connection limit. */
const SWEEP_CONCURRENCY = 6;

/** An agent question: offered options, or a blocking ask. */
export function isAgentAsk(message: Pick<MessageRow, 'direction' | 'mode' | 'metadata'>): boolean {
  if (message.direction !== 'agent_to_boss') return false;
  if (message.mode === 'blocking') return true;
  try {
    const metadata = JSON.parse(message.metadata ?? 'null') as Record<string, unknown> | null;
    return Array.isArray(metadata?.options);
  } catch {
    return false;
  }
}

/** The audience of the ask's original push: devices of every live boss who can read the agent. */
async function audience(env: Env, agentId: string): Promise<PushDevice[]> {
  const rows = await env.DB.prepare(`SELECT d.boss_id, d.device_token, d.bundle_id, d.environment,
      d.relay_handle, d.push_key FROM boss_devices d JOIN bosses b ON b.id = d.boss_id
    WHERE b.archived_at IS NULL AND (b.role = 'admin'
      OR b.id IN (SELECT boss_id FROM boss_agent_access WHERE agent_id = ?))`)
    .bind(agentId).all<PushDevice>();
  return rows.results ?? [];
}

/** Call once after the transition to `replied` or `expired` has committed. */
export async function announceResolution(env: Env, message: ResolvedAsk,
  status: Resolution['status']): Promise<void> {
  try {
    const mode = pushMode(env);
    if (mode === 'none' || !isAgentAsk(message)) return;
    const resolution: Resolution = { id: message.id, status };
    // Concurrent and settled per device: one failed or slow push must not block the others.
    const devices = await audience(env, message.agent_id);
    await Promise.allSettled(devices.map((device) => sendDeviceResolution(env, device, resolution)));
    if (mode === 'direct') {
      await endLiveActivities(env, message, status, new Set(devices.map((device) => device.boss_id)));
    }
  } catch {
    // swallow: the ask is already closed; the app reconciles on its next launch
  }
}

/** Request routes: the response never waits; the Worker keeps the fan-out alive after it. */
export function deferredAnnounce(ctx: Pick<ExecutionContext, 'waitUntil'>): Announce {
  return async (env, message, status) => { ctx.waitUntil(announceResolution(env, message, status)); };
}

/** Collects a scheduled run's resolutions so the fan-out cannot spend the transitions' budget. */
export class ResolutionSweep {
  private readonly pending: { message: ResolvedAsk; status: Resolution['status'] }[] = [];

  readonly announce: Announce = async (_env, message, status) => {
    this.pending.push({ message, status });
  };

  /** Sends the newest SWEEP_RESOLUTION_LIMIT resolutions, a few asks at a time; skips the rest. */
  async flush(env: Env): Promise<void> {
    // SQLite and ISO timestamps share the same sortable first 19 characters once 'T' is a space.
    const key = (item: { message: ResolvedAsk }) => item.message.created_at.slice(0, 19).replace('T', ' ');
    const queue = this.pending.splice(0).sort((a, b) => key(b).localeCompare(key(a)))
      .slice(0, SWEEP_RESOLUTION_LIMIT);
    const worker = async () => {
      for (let item = queue.shift(); item; item = queue.shift()) {
        await announceResolution(env, item.message, item.status);
      }
    };
    await Promise.all(Array.from({ length: SWEEP_CONCURRENCY }, worker));
  }
}
