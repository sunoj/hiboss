// Parses the optional session identity fields of POST /api/sessions and
// admits a parent session only when its agent shares the caller's device.
// Exports parseSessionIdentity and ADMITTED_PARENT_SQL.

export interface SessionIdentity {
  host: string | null;
  runtime: string | null;
  dispatchRef: string | null;
  parentSessionId: string | null;
}

const RUNTIME = /^[a-z][a-z0-9_-]{0,15}$/;
const PRINTABLE = /^[\x21-\x7e]+$/;

function optionalText(value: unknown, name: string, max: number, pattern: RegExp): string | null | Error {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') return new Error(`${name} must be a string`);
  const text = value.trim();
  if (!text) return null;
  if (text.length > max || !pattern.test(text)) return new Error(`${name} is malformed`);
  return text;
}

/** Returns the identity fields, or an error message for a malformed one. */
export function parseSessionIdentity(payload: Record<string, unknown>): SessionIdentity | string {
  const host = optionalText(payload.host, 'host', 64, PRINTABLE);
  const runtime = optionalText(payload.runtime, 'runtime', 16, RUNTIME);
  const dispatchRef = optionalText(payload.dispatch_ref, 'dispatch_ref', 128, PRINTABLE);
  const parentSessionId = optionalText(payload.parent_session_id, 'parent_session_id', 128, PRINTABLE);
  for (const field of [host, runtime, dispatchRef, parentSessionId]) {
    if (field instanceof Error) return field.message;
  }
  return { host, runtime, dispatchRef, parentSessionId } as SessionIdentity;
}

/**
 * SQL for the parent to store, evaluated inside the session upsert so the check and the
 * write are one statement. Binds (agentId, parentId, sessionId, sessionId). It yields the
 * parent id only when the parent exists, is not the session itself, has no parent of its
 * own, the session has no children, and the parent's agent has the caller's non-null
 * device; otherwise NULL. Parents are roots and children are leaves, so depth stays 1.
 */
export const ADMITTED_PARENT_SQL = `(SELECT ps.id FROM sessions ps
    JOIN api_keys pa ON pa.id = ps.agent_id
    JOIN api_keys me ON me.id = ?
   WHERE ps.id = ? AND ps.id <> ? AND ps.parent_session_id IS NULL
     AND pa.device_id IS NOT NULL AND pa.device_id = me.device_id
     AND NOT EXISTS (SELECT 1 FROM sessions k WHERE k.parent_session_id = ?))`;
