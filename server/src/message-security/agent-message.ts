// Admits agent message writes: verifies signed JWS content and forbids unsigned downgrades.
// Exports authenticateAgentMessage and the signed content contract.
// Depends on the agent key registry, compact JWS helpers and provenance builders.

import type { Env } from '../types';
import { agentRequiresSignature, findLiveKeyForCredential } from './agent-keys';
import { isFresh, verifyCompactJws } from './jws';
import { agentBearerProvenance, agentSignedProvenance } from './provenance';

export const AGENT_MESSAGE_TYPE = 'hiboss-agent-message+jws';
const AGENT_MESSAGE_PURPOSE = 'hiboss.agent-message';
const MESSAGE_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ENVELOPE_KEYS = ['version', 'purpose', 'message_id', 'issued_at', 'agent_id'] as const;
const CONTENT_KEYS = ['session_id', 'action', 'body', 'mode', 'timeout', 'file_url', 'options', 'metadata'] as const;

/** The resolved recipient; peers are bound by ID so a stored row cannot be re-addressed. */
export type AgentAudience =
  | { readonly kind: 'boss' }
  | { readonly kind: 'agent'; readonly agent_id: string; readonly session_id: string | null };

export type AgentAction =
  | { readonly kind: 'send'; readonly audience: AgentAudience }
  | { readonly kind: 'reply'; readonly message_id: string; readonly audience: AgentAudience }
  | { readonly kind: 'boss_reply'; readonly message_id: string }
  | { readonly kind: 'forward'; readonly message_id: string; readonly channel: string };

export function audienceOf(direction: string, agentId: string | null, sessionId: string | null): AgentAudience {
  return direction === 'agent_to_agent' && agentId
    ? { kind: 'agent', agent_id: agentId, session_id: sessionId }
    : { kind: 'boss' };
}

/** The request content a signature must cover, in the server's normalized form. */
export interface SignedAgentContent {
  readonly session_id: string | null;
  readonly action: AgentAction;
  readonly body: string;
  readonly mode: 'async' | 'blocking' | null;
  readonly timeout: number | null;
  readonly file_url: string | null;
  readonly options: readonly string[] | null;
  readonly metadata: Record<string, unknown> | null;
}

export interface AgentMessageInput {
  readonly env: Env;
  readonly agentId: string;
  readonly agentKeyId: string | null;
  readonly signedMessage: unknown;
  readonly content: SignedAgentContent;
}

export type AgentMessageAuthResult =
  | { readonly ok: true; readonly signed: { readonly keyId: string; readonly messageId: string } | null;
      readonly metadata: Record<string, unknown> }
  | { readonly ok: false; readonly status: 400 | 401; readonly error: string };

export async function authenticateAgentMessage(input: AgentMessageInput): Promise<AgentMessageAuthResult> {
  const key = input.agentKeyId ? await findLiveKeyForCredential(input.env, input.agentKeyId) : null;
  if (!key) {
    if (input.signedMessage !== undefined) return failure(400, 'signing key not registered for this credential');
    if (await agentRequiresSignature(input.env, input.agentId)) {
      return failure(401, 'signed message required: this agent signs its messages; run `hiboss key enroll` on this device');
    }
    return { ok: true, signed: null, metadata: agentBearerProvenance(input.agentId, input.agentKeyId) };
  }
  if (typeof input.signedMessage !== 'string' || !input.signedMessage) {
    return failure(401, 'signed message required: update the hiboss CLI or MCP plugin');
  }
  const payload = await verifyCompactJws(
    input.signedMessage, { keyId: key.key_id, publicKey: key.public_key }, AGENT_MESSAGE_TYPE,
  );
  if (!payload || !hasEnvelope(payload)) return failure(401, 'invalid signed message');
  if (payload['agent_id'] !== input.agentId) return failure(401, 'signed message agent mismatch');
  if (!matchesContent(payload, input.content)) return failure(401, 'signed message does not match request');
  if (!isFresh(payload['issued_at'] as number)) return failure(401, 'stale signed message');
  const messageId = payload['message_id'] as string;
  return {
    ok: true,
    signed: { keyId: key.key_id, messageId },
    metadata: agentSignedProvenance(input.agentId, key, input.signedMessage),
  };
}

/** Content of a signed write whose only signed fields are the action and the body. */
export function actionContent(action: AgentAction, body: string): SignedAgentContent {
  return { session_id: null, action, body, mode: null, timeout: null, file_url: null, options: null, metadata: null };
}

/** The idempotency key that makes a replayed signed write return the original row. */
export function signedIdempotencyKey(signed: { keyId: string; messageId: string }): string {
  return `sig:${signed.keyId}:${signed.messageId}`;
}

function hasEnvelope(payload: Record<string, unknown>): boolean {
  const keys = Object.keys(payload);
  const expected = [...ENVELOPE_KEYS, ...CONTENT_KEYS];
  return keys.length === expected.length && expected.every(key => keys.includes(key))
    && payload['version'] === 1
    && payload['purpose'] === AGENT_MESSAGE_PURPOSE
    && typeof payload['message_id'] === 'string' && MESSAGE_ID_PATTERN.test(payload['message_id'])
    && Number.isInteger(payload['issued_at']);
}

function matchesContent(payload: Record<string, unknown>, content: SignedAgentContent): boolean {
  return CONTENT_KEYS.every(key => deepEqual(payload[key], content[key]));
}

export function deepEqual(left: unknown, right: unknown): boolean {
  if (left === right) return true;
  if (Array.isArray(left) || Array.isArray(right)) {
    return Array.isArray(left) && Array.isArray(right) && left.length === right.length
      && left.every((value, index) => deepEqual(value, right[index]));
  }
  if (!left || !right || typeof left !== 'object' || typeof right !== 'object') return false;
  const a = left as Record<string, unknown>;
  const b = right as Record<string, unknown>;
  const keys = Object.keys(a);
  return keys.length === Object.keys(b).length && keys.every(key => Object.hasOwn(b, key) && deepEqual(a[key], b[key]));
}

function failure(status: 400 | 401, error: string): AgentMessageAuthResult {
  return { ok: false, status, error };
}
