// Shared join approval helpers for Telegram and Discord callbacks.
// Exports join callback parsing and approve/reject operations.
// Depends on Env typings and auth hashing.

import type { Env } from '../types';
import { hashApiKey } from '../middleware/auth';

export type JoinCallbackAction = 'approve' | 'reject';

export type JoinCallbackResult = {
  answerText: string;
  auditAction: string;
  auditDetails: string;
  joinStatus: 'approved' | 'rejected';
  messageText: string;
  statusCode: 200 | 404 | 409;
  error?: string;
  apiKeyId?: string;
};

export function parseJoinCallbackData(data: string): { action: JoinCallbackAction; requestId: string } | null {
  const match = /^join:(approve|reject):([0-9a-f]{32})$/i.exec(data);
  if (!match) {
    return null;
  }
  return { action: match[1].toLowerCase() as JoinCallbackAction, requestId: match[2].toLowerCase() };
}

export async function approveJoinRequest(env: Env, requestId: string): Promise<JoinCallbackResult> {
  const joinRequest = await env.DB
    .prepare('SELECT id, name, status FROM join_requests WHERE id = ?')
    .bind(requestId)
    .first<{ id: string; name: string; status: string }>();
  if (!joinRequest) {
    return joinErrorResult('Not found', 'join request not found', 404);
  }
  if (joinRequest.status !== 'pending') {
    return joinErrorResult(`Already ${joinRequest.status}`, `join request already ${joinRequest.status}`, 409);
  }
  const key = `hb_${generateHex(16)}`;
  const keyHash = await hashApiKey(key);
  const apiKey = await env.DB
    .prepare('INSERT INTO api_keys (name, key_hash) VALUES (?, ?) RETURNING id')
    .bind(joinRequest.name, keyHash)
    .first<{ id: string }>();
  if (!apiKey) {
    return joinErrorResult('Error', 'failed to create api key', 409);
  }
  const update = await env.DB
    .prepare("UPDATE join_requests SET status = 'approved', api_key_id = ?, api_key = ?, updated_at = datetime('now') WHERE id = ? AND status = 'pending'")
    .bind(apiKey.id, key, requestId)
    .run();
  if (!update.meta.changes) {
    await env.DB.prepare('DELETE FROM api_keys WHERE id = ?').bind(apiKey.id).run();
    return joinErrorResult('Already handled', 'join request no longer pending', 409);
  }
  return {
    answerText: '✅ Approved',
    auditAction: 'join_request.approve',
    auditDetails: joinRequest.name,
    joinStatus: 'approved',
    messageText: '✅ Approved',
    statusCode: 200,
    apiKeyId: apiKey.id,
  };
}

export async function rejectJoinRequest(env: Env, requestId: string): Promise<JoinCallbackResult> {
  const joinRequest = await env.DB
    .prepare('SELECT name, status FROM join_requests WHERE id = ?')
    .bind(requestId)
    .first<{ name: string; status: string }>();
  if (!joinRequest) {
    return joinErrorResult('Not found', 'join request not found', 404);
  }
  if (joinRequest.status !== 'pending') {
    return joinErrorResult(`Already ${joinRequest.status}`, `join request already ${joinRequest.status}`, 409);
  }
  const update = await env.DB
    .prepare("UPDATE join_requests SET status = 'rejected', updated_at = datetime('now') WHERE id = ? AND status = 'pending'")
    .bind(requestId)
    .run();
  if (!update.meta.changes) {
    return joinErrorResult('Already handled', 'join request no longer pending', 409);
  }
  return {
    answerText: '❌ Rejected',
    auditAction: 'join_request.reject',
    auditDetails: joinRequest.name,
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
