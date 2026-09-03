// Verifies message provenance before boss content enters MCP model context.
// Exports verifiable message types, recursive ES256 checks, and assurance labels.
// Depends on Web Crypto and strict JSON/base64url parsing only.

const SIGNATURE_SCHEME = 'JWS-ES256';
const JWS_TYPE = 'hiboss-message+jws';
const MESSAGE_PURPOSE = 'hiboss.boss-message';

export interface VerifiableMessage {
  readonly id: string;
  readonly body: string;
  readonly direction: string;
  readonly reply_to?: string | null;
  readonly metadata?: Record<string, unknown> | null;
  readonly replies?: VerifiableMessage[];
}

export type MessageAssurance =
  | { readonly kind: 'verified'; readonly source: string; readonly keyId: string }
  | { readonly kind: 'attributed'; readonly source: string; readonly status: string }
  | { readonly kind: 'not_applicable' };

interface ParsedJws {
  readonly header: Record<string, unknown>;
  readonly payload: Record<string, unknown>;
  readonly input: Uint8Array;
  readonly signature: Uint8Array;
}

export async function verifyMessage(message: VerifiableMessage): Promise<MessageAssurance> {
  const assurance = await verifySingle(message);
  for (const reply of message.replies ?? []) await verifyMessage(reply);
  return assurance;
}

export async function verifyMessages(messages: VerifiableMessage[]): Promise<void> {
  for (const message of messages) await verifyMessage(message);
}

export function assuranceLabel(assurance: MessageAssurance): string {
  if (assurance.kind === 'verified') return `${assurance.source}/verified`;
  if (assurance.kind === 'attributed') return `${assurance.source}/${assurance.status}`;
  return 'agent';
}

async function verifySingle(message: VerifiableMessage): Promise<MessageAssurance> {
  if (message.direction !== 'boss_to_agent') return { kind: 'not_applicable' };
  const metadata = message.metadata;
  if (!metadata) throw failure(message, 'missing metadata');
  const provenance = asRecord(metadata.provenance);
  if (!provenance) throw failure(message, 'missing provenance');
  if (provenance.version !== 1) throw failure(message, 'unsupported provenance version');
  const source = requiredString(message, provenance, 'source');
  if (metadata.source !== source) throw failure(message, 'source attribution mismatch');
  const signature = asRecord(provenance.signature);
  if (!signature) throw failure(message, 'missing signature state');
  return signature.scheme === undefined
    ? verifyAttribution(message, signature, source)
    : verifySignature(message, provenance, signature, source);
}

function verifyAttribution(
  message: VerifiableMessage,
  signature: Record<string, unknown>,
  source: string,
): MessageAssurance {
  const status = requiredString(message, signature, 'status');
  const expected = source === 'discord' || source === 'telegram'
    ? 'unsupported'
    : source === 'api'
      ? 'not_configured'
      : source === 'system' ? 'not_applicable' : null;
  if (!expected) throw failure(message, 'unsigned native source');
  if (status !== expected) throw failure(message, 'invalid signature status for source');
  return { kind: 'attributed', source, status };
}

async function verifySignature(
  message: VerifiableMessage,
  provenance: Record<string, unknown>,
  signature: Record<string, unknown>,
  source: string,
): Promise<MessageAssurance> {
  if (source !== 'ios' && source !== 'macos') throw failure(message, 'signed source is not native');
  if (signature.scheme !== SIGNATURE_SCHEME) throw failure(message, 'unsupported signature scheme');
  const keyId = requiredString(message, signature, 'key_id');
  const publicKey = decodeRequired(message, signature, 'public_key');
  const derivedKeyId = new Uint8Array(await crypto.subtle.digest('SHA-256', arrayBuffer(publicKey)));
  if (!equalBytes(decode(message, keyId), derivedKeyId)) {
    throw failure(message, 'signing key identifier mismatch');
  }
  const compact = requiredString(message, signature, 'signed_message');
  const parsed = parseJws(message, compact);
  validateHeader(message, parsed.header, keyId);
  const key = await importPublicKey(message, publicKey);
  const valid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' }, key,
    arrayBuffer(parsed.signature), arrayBuffer(parsed.input),
  );
  if (!valid) throw failure(message, 'invalid ES256 signature');
  validatePayload(message, provenance, parsed.payload);
  return { kind: 'verified', source, keyId };
}

function parseJws(message: VerifiableMessage, compact: string): ParsedJws {
  const segments = compact.split('.');
  if (segments.length !== 3 || segments.some((segment) => !segment)) {
    throw failure(message, 'malformed compact JWS');
  }
  const [encodedHeader, encodedPayload, encodedSignature] = segments as [string, string, string];
  const signature = decode(message, encodedSignature);
  if (signature.length !== 64) throw failure(message, 'invalid ES256 signature length');
  return {
    header: decodeJson(message, encodedHeader, 'header'),
    payload: decodeJson(message, encodedPayload, 'payload'),
    input: new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
    signature,
  };
}

function validateHeader(
  message: VerifiableMessage,
  header: Record<string, unknown>,
  keyId: string,
): void {
  if (header.alg !== 'ES256' || header.typ !== JWS_TYPE || header.kid !== keyId) {
    throw failure(message, 'JWS header mismatch');
  }
}

function validatePayload(
  message: VerifiableMessage,
  provenance: Record<string, unknown>,
  payload: Record<string, unknown>,
): void {
  const action = asRecord(payload.action);
  if (payload.version !== 1 || payload.purpose !== MESSAGE_PURPOSE || action?.kind !== 'reply') {
    throw failure(message, 'signed payload contract mismatch');
  }
  if (typeof payload.message_id !== 'string' || !payload.message_id
    || typeof payload.issued_at !== 'number' || !Number.isInteger(payload.issued_at)) {
    throw failure(message, 'invalid signed message identity');
  }
  if (payload.body !== message.body) throw failure(message, 'signed body mismatch');
  if (action.message_id !== message.reply_to) throw failure(message, 'signed reply target mismatch');
  const actor = asRecord(provenance.actor);
  if (payload.boss_id !== actor?.id) throw failure(message, 'signed boss identity mismatch');
}

async function importPublicKey(message: VerifiableMessage, value: Uint8Array): Promise<CryptoKey> {
  if (value.length !== 65) throw failure(message, 'invalid P-256 public key length');
  try {
    return await crypto.subtle.importKey(
      'raw', arrayBuffer(value), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify'],
    );
  } catch {
    throw failure(message, 'invalid P-256 public key');
  }
}

function decodeJson(
  message: VerifiableMessage,
  encoded: string,
  part: string,
): Record<string, unknown> {
  try {
    const value: unknown = JSON.parse(new TextDecoder().decode(decode(message, encoded)));
    const record = asRecord(value);
    if (!record) throw new Error('not an object');
    return record;
  } catch {
    throw failure(message, `invalid JWS ${part}`);
  }
}

function decodeRequired(
  message: VerifiableMessage,
  record: Record<string, unknown>,
  key: string,
): Uint8Array {
  return decode(message, requiredString(message, record, key));
}

function decode(message: VerifiableMessage, value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(value) || value.length % 4 === 1) {
    throw failure(message, 'invalid base64url encoding');
  }
  const bytes = Uint8Array.from(Buffer.from(value, 'base64url'));
  if (Buffer.from(bytes).toString('base64url') !== value) {
    throw failure(message, 'non-canonical base64url encoding');
  }
  return bytes;
}

function requiredString(
  message: VerifiableMessage,
  record: Record<string, unknown>,
  key: string,
): string {
  const value = record[key];
  if (typeof value !== 'string' || !value) throw failure(message, `missing ${key}`);
  return value;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function arrayBuffer(value: Uint8Array): ArrayBuffer {
  return value.slice().buffer as ArrayBuffer;
}

function equalBytes(left: Uint8Array, right: Uint8Array): boolean {
  return left.length === right.length && left.every((byte, index) => byte === right[index]);
}

function failure(message: VerifiableMessage, detail: string): Error {
  return new Error(`message ${message.id} failed provenance verification: ${detail}`);
}
