// Shared join approval helpers for Telegram and Discord callbacks.
// Exports join callback parsing and approve/reject operations.
// Depends on Env typings and the atomic device approval in devices/approve.

import type { Env } from '../types';
import { approveJoin, rejectJoin } from '../devices/approve';

export type JoinCallbackAction = 'approve' | 'reject';

export type JoinCallbackResult = {
  answerText: string;
  auditAction: string;
  auditDetails: string;
  joinStatus: 'approved' | 'rejected';
  messageText: string;
  statusCode: 200 | 404 | 409;
  error?: string;
  agentIds?: string[];
};

export function parseJoinCallbackData(data: string): { action: JoinCallbackAction; requestId: string } | null {
  const match = /^join:(approve|reject):([0-9a-f]{32})$/i.exec(data);
  if (!match) {
    return null;
  }
  return { action: match[1].toLowerCase() as JoinCallbackAction, requestId: match[2].toLowerCase() };
}

export async function approveJoinRequest(env: Env, requestId: string, approverBossId?: string): Promise<JoinCallbackResult> {
  const actor = approverBossId ? { type: 'boss' as const, id: approverBossId } : { type: 'system' as const, id: 'join' };
  const outcome = await approveJoin(env.DB, requestId, actor, { approverBossId });
  if (!outcome.ok) {
    const answer = outcome.status === 404 ? 'Not found' : outcome.error.includes('name') ? 'Name already exists' : 'Already handled';
    return joinErrorResult(answer, outcome.error, outcome.status);
  }
  return {
    answerText: '✅ Approved',
    auditAction: 'join_request.approve',
    auditDetails: outcome.agents.map(agent => agent.name).join(', '),
    joinStatus: 'approved',
    messageText: '✅ Approved',
    statusCode: 200,
    agentIds: outcome.agents.map(agent => agent.agent_id),
  };
}

export async function rejectJoinRequest(env: Env, requestId: string): Promise<JoinCallbackResult> {
  const outcome = await rejectJoin(env.DB, requestId);
  if (!outcome.ok) return joinErrorResult(outcome.status === 404 ? 'Not found' : 'Already handled', outcome.error, outcome.status);
  return {
    answerText: '❌ Rejected',
    auditAction: 'join_request.reject',
    auditDetails: requestId,
    joinStatus: 'rejected',
    messageText: '❌ Rejected',
    statusCode: 200,
  };
}

export function joinErrorResult(answerText: string, error: string, statusCode: 404 | 409): JoinCallbackResult {
  return {
    answerText,
    auditAction: 'join_request.error',
    auditDetails: error,
    joinStatus: 'rejected',
    messageText: answerText,
    statusCode,
    error,
  };
}

export function generateHex(bytes: number): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf)
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');
}
