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
  // Unread: boss messages for this agent, agent-to-agent targeting this agent, or session-targeted messages
  if (unread) {
    if (direction === 'agent_to_agent') {
      // Narrowed unread: only agent-to-agent messages targeting this agent/session
      if (targetSessionId) {
        clauses.push("((target_agent_id = ? AND direction = 'agent_to_agent' AND target_session_id IS NULL) OR (target_session_id = ? AND direction = 'agent_to_agent'))");
        binds.push(agentId, targetSessionId);
      } else {
        clauses.push("(target_agent_id = ? AND direction = 'agent_to_agent')");
        binds.push(agentId);
      }
    } else if (targetSessionId) {
      clauses.push("((agent_id = ? AND direction = 'boss_to_agent') OR (target_agent_id = ? AND direction = 'agent_to_agent' AND target_session_id IS NULL) OR (target_session_id = ? AND direction = 'agent_to_agent'))");
      binds.push(agentId, agentId, targetSessionId);
    } else {
      clauses.push("((agent_id = ? AND direction = 'boss_to_agent') OR (target_agent_id = ? AND direction = 'agent_to_agent'))");
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
    // and boss-initiated messages (reply_to IS NULL) visible to all sessions.
    clauses.push("(session_id = ? OR reply_to IN (SELECT id FROM messages WHERE session_id = ?) OR (direction = 'boss_to_agent' AND reply_to IS NULL))");
    binds.push(session, session);
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
