// Builds size-bounded message snapshots for APNs cache prewarming.
// Exports: attachMessageSnapshot and its typed context contract.
// Dependencies: APNs payload and persisted message row contracts.

import type { ApnsPayload } from '../apns';
import type { MessageRow } from '../types';

const MAX_SNAPSHOT_PAYLOAD_BYTES = 4_000;

export interface MessageSnapshotContext {
  readonly agentName: string;
  readonly sessionLabel: string | null;
  readonly sessionBranch: string | null;
}

export function attachMessageSnapshot(
  payload: ApnsPayload,
  message: MessageRow,
  context: MessageSnapshotContext,
): ApnsPayload {
  const candidate: ApnsPayload = {
    ...payload,
    message: buildMessageSnapshot(message, context),
  };
  return payloadSize(candidate) <= MAX_SNAPSHOT_PAYLOAD_BYTES ? candidate : payload;
}

function buildMessageSnapshot(
  message: MessageRow,
  context: MessageSnapshotContext,
): Record<string, unknown> {
  const snapshot: Record<string, unknown> = {
    id: message.id,
    body: message.body,
    agent_name: context.agentName,
    direction: message.direction,
    status: message.status,
    priority: message.priority,
    created_at: message.created_at,
  };
  addOptional(snapshot, 'channel', message.channel);
  addOptional(snapshot, 'mode', message.mode);
  addOptional(snapshot, 'type', message.type);
  addOptional(snapshot, 'reply_to', message.reply_to);
  addOptional(snapshot, 'expires_at', message.expires_at);
  addOptional(snapshot, 'session_id', message.session_id);
  addOptional(snapshot, 'target_session_id', message.target_session_id);
  addOptional(snapshot, 'session_label', context.sessionLabel);
  addOptional(snapshot, 'session_branch', context.sessionBranch);
  const metadata = parseMetadata(message.metadata);
  if (metadata) snapshot.metadata = metadata;
  return snapshot;
}

function addOptional(target: Record<string, unknown>, key: string, value: string | null | undefined): void {
  if (value !== null && value !== undefined) target[key] = value;
}

function parseMetadata(raw: string | null): Record<string, unknown> | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as unknown;
    return parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

function payloadSize(payload: ApnsPayload): number {
  return new TextEncoder().encode(JSON.stringify(payload)).byteLength;
}
