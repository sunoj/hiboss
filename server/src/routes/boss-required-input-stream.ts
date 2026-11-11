// Live required-input discovery for iOS, independent of the macOS option stream.
// Exports streamBossRequiredInputs; depends on complete scoped keyset discovery.
// Emits ready after the first full scan; later polls read only changed and tracked rows.

import type { Env, MessageResponse } from '../types';
import { fetchAllRequiredInputs, fetchRequiredInputChanges } from './boss-required-inputs';
import { DEFAULT_BOSS_STREAM_POLL_INTERVAL_MS, getStreamPollIntervalMs } from './stream-config';

const KEEPALIVE_MS = 15_000;
const MAX_DURATION_MS = 5 * 60_000;
// Rows updated this long before a poll began are read again, covering clock skew between the
// Worker and D1 and second-granular updated_at; repeated rows are filtered by payload.
const CHANGE_MARGIN_MS = 30_000;

export async function streamBossRequiredInputs(
  writer: WritableStreamDefaultWriter, encoder: TextEncoder, env: Env, agentIds: string[],
): Promise<void> {
  const started = Date.now();
  let keepalive = started;
  let tracked = new Map<string, MessageResponse>();
  let initial = true;
  let since = '';
  const pollMs = getStreamPollIntervalMs(env, DEFAULT_BOSS_STREAM_POLL_INTERVAL_MS);
  try {
    while (Date.now() - started < MAX_DURATION_MS) {
      const pollStarted = sqlTime(Date.now() - CHANGE_MARGIN_MS);
      const messages = initial
        ? await fetchAllRequiredInputs(env, agentIds)
        : await fetchRequiredInputChanges(env, agentIds, [...tracked.keys()], since);
      since = pollStarted;
      const current = new Map(messages.map((message) => [message.id, message]));
      for (const message of messages) {
        const prior = tracked.get(message.id);
        if (!prior || JSON.stringify(prior) !== JSON.stringify(message)) {
          await writeEvent(writer, encoder, 'message', message);
        }
      }
      for (const id of tracked.keys()) {
        if (!current.has(id)) await writeEvent(writer, encoder, 'resolved', { id });
      }
      tracked = current;
      if (initial) {
        await writeEvent(writer, encoder, 'ready', {});
        initial = false;
      }
      if (Date.now() - keepalive >= KEEPALIVE_MS) {
        await writer.write(encoder.encode(': keepalive\n\n'));
        keepalive = Date.now();
      }
      await new Promise((resolve) => setTimeout(resolve, pollMs));
    }
  } catch {
    // A disconnected client owns no shared delivery state.
  } finally {
    try { await writer.close(); } catch { /* Already closed. */ }
  }
}

function sqlTime(milliseconds: number): string {
  return new Date(milliseconds).toISOString().replace('T', ' ').slice(0, 19);
}

async function writeEvent(
  writer: WritableStreamDefaultWriter, encoder: TextEncoder,
  event: 'message' | 'resolved' | 'ready', payload: unknown,
): Promise<void> {
  await writer.write(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`));
}
