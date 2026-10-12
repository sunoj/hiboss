// Verifies agent-authored message provenance before peer content enters MCP model context.
// Exports verifyAgentRow (agent rows) and verifyAgentSignature (signed agent JWS checks).
// Mirrors cli/src/agent_provenance.rs; depends on shared helpers in message-security.

import {
  SIGNATURE_SCHEME, arrayBuffer, asRecord, decode, decodeRequired, equalBytes, failure, importPublicKey,
  parseJws, requiredString, verifyAttribution, type MessageAssurance, type VerifiableMessage,
} from './message-security.js';

const JWS_TYPE = 'hiboss-agent-message+jws';
const PURPOSE = 'hiboss.agent-message';
const MAX_SKEW_SECONDS = 300;
const SIGNED_METADATA = ['content', 'summary', 'default_option', 'task_context'];

/** Rows without provenance predate attribution; any provenance present must hold. */
export async function verifyAgentRow(message: VerifiableMessage): Promise<MessageAssurance> {
  const provenance = asRecord(message.metadata?.provenance);
  if (message.metadata?.provenance === undefined) return { kind: 'not_applicable' };
  if (!provenance || provenance.version !== 1) throw failure(message, 'unsupported provenance version');
  const source = requiredString(message, provenance, 'source');
  if (message.metadata?.source !== source) throw failure(message, 'source attribution mismatch');
  if (source !== 'agent' && source !== 'system') throw failure(message, 'agent message carries a non-agent source');
  const signature = asRecord(provenance.signature);
  if (!signature) throw failure(message, 'missing signature state');
  return signature.scheme === undefined
    ? verifyAttribution(message, signature, source)
    : verifyAgentSignature(message, provenance, signature);
}

export async function verifyAgentSignature(
  message: VerifiableMessage,
  provenance: Record<string, unknown>,
  signature: Record<string, unknown>,
): Promise<MessageAssurance> {
  if (signature.scheme !== SIGNATURE_SCHEME) throw failure(message, 'unsupported signature scheme');
  const keyId = requiredString(message, signature, 'key_id');
  const publicKey = decodeRequired(message, signature, 'public_key');
  const derived = new Uint8Array(await crypto.subtle.digest('SHA-256', arrayBuffer(publicKey)));
  if (!equalBytes(decode(message, keyId), derived)) throw failure(message, 'signing key identifier mismatch');
  const parsed = parseJws(message, requiredString(message, signature, 'signed_message'));
  if (parsed.header.alg !== 'ES256' || parsed.header.typ !== JWS_TYPE || parsed.header.kid !== keyId) {
    throw failure(message, 'JWS header mismatch');
  }
  const key = await importPublicKey(message, publicKey);
  const valid = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key,
    arrayBuffer(parsed.signature), arrayBuffer(parsed.input));
  if (!valid) throw failure(message, 'invalid ES256 signature');
  const payload = parsed.payload;
  if (payload.version !== 1 || payload.purpose !== PURPOSE || typeof payload.message_id !== 'string'
    || !Number.isInteger(payload.issued_at)) throw failure(message, 'signed payload contract mismatch');
  const actor = asRecord(provenance.actor)?.id;
  if (typeof actor !== 'string' || payload.agent_id !== actor) throw failure(message, 'signed agent identity mismatch');
  checkContent(message, payload, actor);
  return { kind: 'verified', source: 'agent', keyId };
}

function checkContent(message: VerifiableMessage, payload: Record<string, unknown>, actor: string): void {
  if (payload.body !== message.body) throw failure(message, 'signed body mismatch');
  const action = asRecord(payload.action);
  const consistent = action?.kind === 'send' ? !message.reply_to && audienceMatches(message, action)
    : action?.kind === 'reply' && message.reply_to === action.message_id && audienceMatches(message, action);
  if (!consistent || message.agent_id !== actor) throw failure(message, 'signed action does not match the message');
  const signed = asRecord(payload.metadata);
  for (const key of SIGNED_METADATA) {
    if (!sameJson(signed?.[key], message.metadata?.[key])) throw failure(message, `signed ${key} mismatch`);
  }
  // Absent and null are the same: a row cannot gain options or a file its signature lacks.
  for (const key of ['options', 'file_url']) {
    if (!sameJson(payload[key] ?? null, message.metadata?.[key] ?? null)) throw failure(message, `signed ${key} mismatch`);
  }
  const created = parseTimestamp(message.created_at);
  if (created === null) throw failure(message, 'signed message has no valid created_at');
  if (Math.abs(created - (payload.issued_at as number)) > MAX_SKEW_SECONDS) {
    throw failure(message, 'signed time does not match the stored message');
  }
}

/** The signed recipient must be the row's: the boss, or the exact peer agent and session. */
function audienceMatches(message: VerifiableMessage, action: Record<string, unknown>): boolean {
  const audience = asRecord(action.audience);
  if (audience?.kind === 'boss') return message.direction === 'agent_to_boss' && untargeted(message);
  return audience?.kind === 'agent' && message.direction === 'agent_to_agent'
    && (message.target_agent_id ?? null) === audience.agent_id
    && (message.target_session_id ?? null) === (audience.session_id ?? null);
}

/** A row addressed to the boss names no peer; a recipient added later would expose it. */
function untargeted(message: VerifiableMessage): boolean {
  return !message.target_agent_id && !message.target_session_id;
}

function sameJson(left: unknown, right: unknown): boolean {
  return JSON.stringify(canonical(left)) === JSON.stringify(canonical(right));
}

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => [k, canonical(v)]));
  }
  return value;
}

/** SQLite `YYYY-MM-DD HH:MM:SS` (UTC) or RFC 3339; null when absent or unparsable. */
function parseTimestamp(value: string | null | undefined): number | null {
  if (!value) return null;
  const normalized = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(value) ? `${value.replace(' ', 'T')}Z` : value;
  const millis = Date.parse(normalized);
  return Number.isNaN(millis) ? null : Math.floor(millis / 1000);
}
