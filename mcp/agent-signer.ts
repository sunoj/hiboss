// Signs agent message requests with the credential's enrolled P-256 key, shared with the CLI.
// Exports signerPath, loadAgentSigner, resolveAudience, signSend and signAction (no-ops until enrolled).
// Depends on Web Crypto, node fs/path/crypto, and the shared config path resolver.

import { createHash, randomUUID } from 'node:crypto';
import { readFileSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { configPath } from './config.js';

const MESSAGE_TYPE = 'hiboss-agent-message+jws';
const SERVER_OWNED = new Set([
  'provenance', 'source', 'boss_id', 'boss_name', 'auto_default', 'ask_deadline',
  'options', 'file_url', 'options_resolved', 'options_expired', 'selected_option', 'reactions',
  'telegram_message_id', 'telegram_chat_id', 'discord_message_id', 'delivery_results', 'delivery_error',
]);

export interface AgentSigner { readonly key: CryptoKey; readonly keyId: string; readonly agentId: string }
type Body = Record<string, unknown>;

/** The CLI's key file for `bearer`: beside the real config, named by a digest of the bearer. */
export function signerPath(bearer: string, env: NodeJS.ProcessEnv = process.env): string {
  const config = configPath(env);
  let real = config;
  try { real = realpathSync(config); } catch { /* config may be env-only */ }
  const name = createHash('sha256').update(bearer).digest('hex').slice(0, 32);
  return join(dirname(real), 'signing', `${name}.json`);
}

export async function loadAgentSigner(bearer: string, env: NodeJS.ProcessEnv = process.env): Promise<AgentSigner | null> {
  let raw: string;
  try {
    raw = readFileSync(signerPath(bearer, env), 'utf8');
  } catch {
    return null;
  }
  const file = JSON.parse(raw) as { version?: unknown; agent_id?: unknown; key_id?: unknown; pkcs8?: unknown };
  if (file.version !== 1 || typeof file.agent_id !== 'string' || typeof file.key_id !== 'string' || typeof file.pkcs8 !== 'string') {
    throw new Error('signing key file is malformed; rerun `hiboss key enroll`');
  }
  const key = await crypto.subtle.importKey('pkcs8', Buffer.from(file.pkcs8, 'base64url'),
    { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  return { key, keyId: file.key_id, agentId: file.agent_id };
}

/** Asks the server which peer `to` names, so the signature can bind the resolved recipient. */
export async function resolveAudience(server: string, bearer: string, to: string, sessionId: string | null): Promise<Body> {
  const response = await fetch(new URL('/api/messages/resolve-target', server), {
    method: 'POST', headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ to, session_id: sessionId }),
  });
  if (!response.ok) throw new Error(`resolve target failed: ${response.status} ${await response.text()}`);
  const target = await response.json() as { agent_id?: unknown; session_id?: unknown };
  if (typeof target.agent_id !== 'string') throw new Error('resolve target returned no agent');
  return { kind: 'agent', agent_id: target.agent_id, session_id: typeof target.session_id === 'string' ? target.session_id : null };
}

/** Normalizes a POST /api/messages body as the server does and attaches `signed_message`. */
export async function signSend(server: string, bearer: string, request: Body, env: NodeJS.ProcessEnv = process.env): Promise<Body> {
  const signer = await loadAgentSigner(bearer, env);
  if (!signer) return request;
  const body = { ...request, body: trimmed(request.body) ?? '' };
  const options = Array.isArray(request.options) ? request.options.map(item => String(item).trim()) : null;
  if (options) body.options = options;
  const to = trimmed(request.to) || null;
  const sessionId = trimmed(request.session_id) || null;
  const audience = to ? await resolveAudience(server, bearer, to, sessionId) : { kind: 'boss' };
  return attach(signer, body, {
    session_id: sessionId,
    action: { kind: 'send', audience },
    body: body.body,
    mode: request.mode === 'blocking' ? 'blocking' : 'async',
    timeout: typeof request.timeout === 'number' ? request.timeout : null,
    file_url: trimmed(request.file_url) || null,
    options,
    metadata: clientMetadata(request.metadata),
  });
}

/** Signs a reply or forward: only the action and the body are signed. */
export async function signAction(bearer: string, request: Body, action: Body,
  env: NodeJS.ProcessEnv = process.env): Promise<Body> {
  const signer = await loadAgentSigner(bearer, env);
  if (!signer) return request;
  const body = { ...request, body: trimmed(request.body) ?? '' };
  return attach(signer, body, {
    session_id: null, action, body: body.body, mode: null, timeout: null, file_url: null, options: null, metadata: null,
  });
}

async function attach(signer: AgentSigner, request: Body, content: Body): Promise<Body> {
  const payload = {
    version: 1, purpose: 'hiboss.agent-message', message_id: randomUUID(),
    issued_at: Math.floor(Date.now() / 1000), agent_id: signer.agentId, ...content,
  };
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const input = `${encode({ alg: 'ES256', kid: signer.keyId, typ: MESSAGE_TYPE })}.${encode(payload)}`;
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, signer.key, new TextEncoder().encode(input));
  const { idempotency_key: _dropped, ...rest } = request;
  return { ...rest, signed_message: `${input}.${Buffer.from(signature).toString('base64url')}` };
}

function clientMetadata(value: unknown): Body | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const kept = Object.fromEntries(Object.entries(value).filter(([key]) => !SERVER_OWNED.has(key)));
  return Object.keys(kept).length > 0 ? kept : null;
}

function trimmed(value: unknown): string | undefined {
  return typeof value === 'string' ? value.trim() : undefined;
}
