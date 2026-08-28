// Helper functions for message route handlers: mapping, validation, and utilities.
// This module re-exports functions from focused modules (queries, options).

import type {
  Channel,
  Direction,
  Env,
  MessageResponse,
  MessageRow,
  Metadata,
  Priority,
  ResolutionSource,
  Status,
} from '../types';

export { 
  deliverReply, 
  deliverToChannelWithOptions, 
  deliverWithRetry, 
  formatAgentMessage, 
  requireDiscordConfig, 
  requireTelegramConfig 
} from './delivery';
export type { DeliveryResult } from './delivery';

const channelOptions: Channel[] = ['discord', 'telegram', 'email', 'api'];
export const priorityOptions: Priority[] = ['critical', 'high', 'normal', 'low'];
export const resolutionSourceOptions: ResolutionSource[] = ['ios', 'macos', 'telegram', 'discord', 'api'];
const LIKE_ESCAPE_PATTERN = /[%_\\]/g;

export function mapMessageRow(row: MessageRow): MessageResponse {
  return {
    ...row,
    metadata: safeParse(row.metadata),
  };
}

export function safeParse(value: string | null): Metadata {
  if (!value) {
    return null;
  }
  try {
    return JSON.parse(value) as Metadata;
  } catch {
    return null;
  }
}

/**
 * Session a boss→agent reply must be scoped to, for conversation affinity.
 * A reply inherits the parent's session so it lands only in the session that
 * authored the parent (parent.session_id for agent_to_boss, or
 * parent.target_session_id when replying within a boss_to_agent chain).
 * Returns null only for parentless/agent-wide messages, which keep broadcast
 * semantics. Without this, a NULL target_session_id fans out to every session
 * under the same agent and the first to poll wins the race (mis-routing).
 */
export function replyTargetSession(
  parent: Pick<MessageRow, 'session_id' | 'target_session_id'>,
): string | null {
  return parent.session_id ?? parent.target_session_id ?? null;
}

export function normalizeMetadata(value: unknown): Metadata {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

export function validateOption<T extends string>(value: unknown, options: readonly T[], fallback?: T): T | null {
  if (typeof value === 'string' && options.includes(value as T)) {
    return value as T;
  }
  if (fallback) {
    return fallback;
  }
  return null;
}

export function validateChannel(value: unknown): Channel | undefined {
  if (typeof value === 'string' && channelOptions.includes(value as Channel)) {
    return value as Channel;
  }
  return undefined;
}

export function validateResolutionSource(value: unknown, fallback: ResolutionSource): ResolutionSource | null {
  if (value === undefined) return fallback;
  return validateOption(value, resolutionSourceOptions);
}

export function buildFilters(
  agentId: string, 
  direction: Direction | null, 
  status: Status | null, 
  priority?: Priority[], 
  type?: string, 
  session?: string, 
  unread?: boolean, 
  from?: string, 
  targetSessionId?: string, 
  search?: string
) {
  const clauses: string[] = [];
  const binds: (string | number)[] = [];
  // Unread: boss messages (status='sent') + a2a messages (status IN 'sent','delivered')
  // Delivered remains unread until the peer explicitly marks it read.
  if (unread) {
    if (direction === 'agent_to_agent') {
      if (targetSessionId) {
        // Exclude self-authored a2a so a session never sees its own broadcasts as unread.
        clauses.push("((target_agent_id = ? AND direction = 'agent_to_agent' AND target_session_id IS NULL) OR (target_session_id = ? AND direction = 'agent_to_agent')) AND (session_id IS NULL OR session_id != ?)");
        binds.push(agentId, targetSessionId, targetSessionId);
      } else {
        clauses.push("(target_agent_id = ? AND direction = 'agent_to_agent')");
        binds.push(agentId);
      }
      clauses.push("status IN ('sent', 'delivered')");
    } else if (targetSessionId) {
      // Self-exclusion (session_id != ?) is scoped to the a2a sub-clauses only;
      // boss_to_agent replies legitimately carry the target session's id.
      clauses.push("((agent_id = ? AND direction = 'boss_to_agent' AND status = 'sent' AND (target_session_id IS NULL OR target_session_id = ?)) OR (target_agent_id = ? AND direction = 'agent_to_agent' AND status IN ('sent', 'delivered') AND target_session_id IS NULL AND (session_id IS NULL OR session_id != ?)) OR (target_session_id = ? AND direction = 'agent_to_agent' AND status IN ('sent', 'delivered') AND (session_id IS NULL OR session_id != ?)))");
      binds.push(agentId, targetSessionId, agentId, targetSessionId, targetSessionId, targetSessionId);
    } else {
      clauses.push("((agent_id = ? AND direction = 'boss_to_agent' AND status = 'sent') OR (target_agent_id = ? AND direction = 'agent_to_agent' AND status IN ('sent', 'delivered')))");
      binds.push(agentId, agentId);
    }
  } else {
    const visibilityClauses = ['agent_id = ?', 'target_agent_id = ?'];
    binds.push(agentId, agentId);
    if (targetSessionId) {
      visibilityClauses.push('(target_session_id = ? AND target_agent_id = ?)');
      binds.push(targetSessionId, agentId);
    }
    clauses.push(`(${visibilityClauses.join(' OR ')})`);
    if (direction) {
      clauses.push('direction = ?');
      binds.push(direction);
    }
  }
  if (status) {
    clauses.push('status = ?');
    binds.push(status);
  }
  if (priority && priority.length > 0) {
    const placeholders = priority.map(() => '?').join(', ');
    clauses.push(`priority IN (${placeholders})`);
    binds.push(...priority);
  }
  if (type) {
    clauses.push('type = ?');
    binds.push(type);
  }
  if (from) {
    clauses.push("agent_id IN (SELECT id FROM api_keys WHERE name = ? OR id LIKE ? ESCAPE '\\')");
    binds.push(from, `${from.replace(LIKE_ESCAPE_PATTERN, '\\$&')}%`);
  }
  if (session && !unread) {
    // Show: messages from this session, boss replies to this session's messages,
    // boss-initiated agent-wide messages, and boss messages targeted to this session.
    clauses.push("(session_id = ? OR reply_to IN (SELECT id FROM messages WHERE session_id = ?) OR (direction = 'boss_to_agent' AND ((reply_to IS NULL AND target_session_id IS NULL) OR target_session_id = ?)))");
    binds.push(session, session, session);
  }
  if (search) {
    clauses.push('body LIKE ?');
    binds.push(`%${search}%`);
  }
  return { where: clauses.join(' AND '), binds };
}

export function parsePriorityFilter(value: string | undefined): Priority[] | undefined {
  if (!value) return undefined;
  const valid: Priority[] = [];
  for (const p of value.split(',')) {
    const trimmed = p.trim() as Priority;
    if (priorityOptions.includes(trimmed)) {
      valid.push(trimmed);
    }
  }
  return valid.length > 0 ? valid : undefined;
}

export function clampNumber(value: string | null | undefined, fallback: number, maximum: number): number {
  const parsed = Number(value ?? fallback);
  if (Number.isNaN(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.min(parsed, maximum);
}

export function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Auto-update session status based on message characteristics. Fire-and-forget. */
export async function inferSessionStatus(
  env: Env,
  agentId: string,
  sessionId: string | null,
  mode: string,
  priority: string,
  body: string,
): Promise<void> {
  if (!sessionId) return;
  let status: string;
  let statusText: string | null = null;
  if (mode === 'blocking') {
    status = 'waiting';
    statusText = 'Waiting for boss reply';
  } else if (priority === 'critical' || priority === 'high') {
    status = 'waiting';
    statusText = body.slice(0, 100);
  } else {
    status = 'working';
    statusText = body.slice(0, 100);
  }
  await env.DB
    .prepare("UPDATE sessions SET status = ?, status_text = ?, last_seen_at = datetime('now') WHERE id = ? AND agent_id = ?")
    .bind(status, statusText, sessionId, agentId)
    .run();
}

export function extractTelegramMessageId(metadata: string | null): number | undefined {
  const meta = safeParse(metadata);
  if (!meta || typeof meta !== 'object') return undefined;
  const record = meta as Record<string, unknown>;
  // Flat key: set by delivery handler (agent_to_boss messages)
  const flat = record['telegram_message_id'];
  if (typeof flat === 'number') return flat;
  // Nested key: raw Telegram payload stored by webhook (boss_to_agent messages)
  const msg = record['message'];
  if (msg && typeof msg === 'object') {
    const id = (msg as Record<string, unknown>)['message_id'];
    if (typeof id === 'number') return id;
  }
  return undefined;
}

// Re-export specialized modules
export * from './message-queries';
export * from './message-options';
