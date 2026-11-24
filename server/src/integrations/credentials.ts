// Generates and verifies Discord-shaped webhook credentials for integration agents.
// Exports newWebhookId, newWebhookToken, findWebhook and the public URL path helper.
// Dependencies: Web Crypto and the agent-key hashing helpers; only hashes are stored.
import { hashApiKey, timingSafeEqual } from '../middleware/auth';

/** A Discord snowflake is 17–20 decimal digits; 19 random digits fit that shape. */
export function newWebhookId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(19));
  const digits = Array.from(bytes, (byte) => String(byte % 10));
  digits[0] = String(1 + (bytes[0] % 9));
  return digits.join('');
}

/** 48 random bytes as base64url: 64 characters, like a Discord webhook token. */
export function newWebhookToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(48));
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_');
}

export const hashWebhookToken = hashApiKey;

export function webhookPath(id: string, token: string): string {
  return `/api/webhooks/${id}/${token}`;
}

export interface WebhookCredential {
  id: string;
  agent_id: string;
  session_id: string;
  label: string;
  priority_cap: 'low' | 'normal' | 'high';
  agent_name: string;
  rate_limit: number | null;
  last_used_at: string | null;
}

/** One primary-key read; an unknown id, a wrong token and a revoked URL look the same. */
export async function findWebhook(db: D1Database, id: string, token: string): Promise<WebhookCredential | null> {
  const row = await db.prepare(`SELECT w.id, w.agent_id, w.session_id, w.label, w.priority_cap, w.token_hash,
      w.last_used_at, a.name AS agent_name, a.rate_limit
    FROM agent_webhooks w JOIN api_keys a ON a.id = w.agent_id
    WHERE w.id = ? AND w.revoked_at IS NULL AND a.kind = 'integration'`)
    .bind(id).first<WebhookCredential & { token_hash: string }>();
  const hash = await hashWebhookToken(token);
  if (!row || !timingSafeEqual(row.token_hash, hash)) return null;
  const { token_hash: _hash, ...credential } = row;
  return credential;
}
