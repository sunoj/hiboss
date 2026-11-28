// Queues app-only boss messages during quiet hours.
// Exports enqueueNativeDelivery; depends on D1 and quiet-hours preferences.
import { destinationsMode } from '../delivery';
import type { Env, MessageRow } from '../types';
import { getAgentQuietHoursEnd } from './quiet-hours';

async function enqueueDelivery(
  env: Env,
  messageId: string,
  agentId: string,
  scheduledAt: Date,
): Promise<void> {
  await env.DB
    .prepare('INSERT INTO delivery_queue (message_id, agent_id, channel, config, scheduled_at) VALUES (?, ?, ?, ?, ?)')
    .bind(messageId, agentId, 'api', JSON.stringify({ native_only: true }), scheduledAt.toISOString())
    .run();
}

export async function enqueueNativeDelivery(env: Env, message: MessageRow): Promise<boolean> {
  if (destinationsMode(env.DESTINATIONS_MODE) === 'on' || message.direction !== 'agent_to_boss'
      || message.priority === 'high' || message.priority === 'critical') return false;
  const quietHoursEnd = await getAgentQuietHoursEnd(env, message.agent_id);
  if (!quietHoursEnd) return false;
  await enqueueDelivery(env, message.id, message.agent_id, quietHoursEnd);
  return true;
}
