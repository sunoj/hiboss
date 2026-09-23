// Live required-input discovery for iOS, independent of the macOS option stream.
// Exports streamBossRequiredInputs; depends on complete scoped keyset discovery.
// Emits ready only after the first full scan has been delivered.

import type { Env, MessageResponse } from '../types';
import { fetchAllRequiredInputs } from './boss-required-inputs';

const POLL_MS = 3_000;
const KEEPALIVE_MS = 15_000;
const MAX_DURATION_MS = 5 * 60_000;

export async function streamBossRequiredInputs(
  writer: WritableStreamDefaultWriter, encoder: TextEncoder, env: Env, agentIds: string[],
): Promise<void> {
  const started = Date.now();
  let keepalive = started;
  let tracked = new Map<string, MessageResponse>();
  let initial = true;
  try {
    while (Date.now() - started < MAX_DURATION_MS) {
      const messages = await fetchAllRequiredInputs(env, agentIds);
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
      await new Promise((resolve) => setTimeout(resolve, POLL_MS));
    }
  } catch {
    // A disconnected client owns no shared delivery state.
  } finally {
    try { await writer.close(); } catch { /* Already closed. */ }
  }
}

async function writeEvent(
  writer: WritableStreamDefaultWriter, encoder: TextEncoder,
  event: 'message' | 'resolved' | 'ready', payload: unknown,
): Promise<void> {
  await writer.write(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`));
}
