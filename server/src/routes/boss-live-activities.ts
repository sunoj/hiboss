// Live Activity push token registration: POST /api/boss/devices/live-activities.
// Exports registerLiveActivity; depends on boss auth context, push mode and D1 device rows.
// Direct mode only: the token is stored for the caller's own direct device and never logged.
// Only an open ask stores a token (409 otherwise), so its close always finds the token to end.
import type { Context } from 'hono';
import type { ApnsEnvironment } from '../apns';
import { getBossId, getBossRole, getClientId } from '../middleware/auth';
import { OPEN_MESSAGE_STATUS } from '../message-status';
import { pushMode } from '../push/send';
import type { Env } from '../types';

interface LiveActivityRegistration {
  messageId: string;
  activityToken: string;
  environment: ApnsEnvironment;
}

const ACTIVITY_TOKEN = /^(?:[0-9a-fA-F]{2}){1,100}$/;

function parseRegistration(value: unknown): LiveActivityRegistration | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const { messageId, activityToken, environment } = value as Record<string, unknown>;
  if (typeof messageId !== 'string' || !messageId || messageId.length > 128) return null;
  if (typeof activityToken !== 'string' || !ACTIVITY_TOKEN.test(activityToken)) return null;
  if (environment !== 'sandbox' && environment !== 'production') return null;
  return { messageId, activityToken: activityToken.toLowerCase(), environment };
}

async function readableMessage(c: Context<{ Bindings: Env }>, messageId: string): Promise<boolean> {
  const row = await c.env.DB.prepare(`SELECT 1 AS found FROM messages WHERE id = ?
    AND (? = 'admin' OR agent_id IN (SELECT agent_id FROM boss_agent_access WHERE boss_id = ?))`)
    .bind(messageId, getBossRole(c), getBossId(c)).first<{ found: number }>();
  return !!row;
}

export async function registerLiveActivity(c: Context<{ Bindings: Env }>): Promise<Response> {
  if (pushMode(c.env) !== 'direct') return c.text('live activity push requires direct APNs', 409);
  const registration = parseRegistration(await c.req.json<unknown>().catch(() => null));
  if (!registration) return c.text('invalid live activity registration', 400);
  if (!await readableMessage(c, registration.messageId)) return c.text('not found', 404);
  const device = await c.env.DB.prepare(`SELECT id FROM boss_devices
    WHERE boss_id = ? AND client_id IS ? AND relay_handle IS NULL ORDER BY last_seen_at DESC LIMIT 1`)
    .bind(getBossId(c), getClientId(c)).first<{ id: string }>();
  if (!device) return c.text('no direct push device registered', 409);
  // Conditional on the ask being open in the same statement: a close commits either before it
  // (nothing stored) or after it (the close's fan-out reads the row).
  const stored = await c.env.DB.prepare(`INSERT INTO live_activity_tokens
      (device_id, message_id, activity_token, environment)
    SELECT ?, id, ?, ? FROM messages WHERE id = ? AND ${OPEN_MESSAGE_STATUS}
    ON CONFLICT(device_id, message_id) DO UPDATE SET
      activity_token = excluded.activity_token, environment = excluded.environment,
      updated_at = datetime('now')`)
    .bind(device.id, registration.activityToken, registration.environment, registration.messageId).run();
  if (stored.meta.changes === 0) return c.text('ask is no longer open', 409);
  return c.body(null, 204);
}
