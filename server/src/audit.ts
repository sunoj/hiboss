// Audit log helper for recording actions across the system.
// Exports logAudit() for fire-and-forget audit writes.
// Depends on D1 Env bindings.

import type { Env } from './types';

type ActorType = 'boss' | 'agent' | 'system';

export async function logAudit(
  env: Env,
  actorType: ActorType,
  actorId: string,
  action: string,
  resourceType?: string,
  resourceId?: string,
  details?: string,
): Promise<void> {
  try {
    await env.DB
      .prepare('INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(actorType, actorId, action, resourceType ?? null, resourceId ?? null, details ?? null)
      .run();
  } catch {
    // Fire-and-forget: audit failures must never block the main request.
  }
}