// Encrypts existing APNs userInfo for the opaque push relay transport.
// Exports credential validation and relay delivery; depends on WebCrypto and fetch.
import type { ApnsPayload, ApnsPriority, ApnsSendResult } from '../apns';

export type PushKind = 'decision' | 'message' | 'system';
const encoder = new TextEncoder();
const MAX_PLAINTEXT = 2048 - 12 - 16;

export function isRelaySecret(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/.test(value);
}

function decode(value: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/') + '='), c => c.charCodeAt(0));
}

function trimmedPayload(payload: ApnsPayload): Uint8Array<ArrayBuffer> {
  const copy = structuredClone(payload);
  const size = () => encoder.encode(JSON.stringify(copy));
  if (size().length <= MAX_PLAINTEXT) return size();
  delete copy.message;
  if (size().length <= MAX_PLAINTEXT) return size();
  // Preserve routing identifiers and category before optional presentation fields.
  for (const key of Object.keys(copy)) {
    const required = ['aps', 'messageId', 'category', 'options', 'join_request_id', 'requestId', 'panelId'];
    if (!required.includes(key)) {
      delete copy[key];
    }
  }
  const alert = copy.aps.alert;
  for (const field of ['subtitle', 'body', 'title'] as const) {
    if (size().length <= MAX_PLAINTEXT) break;
    const characters = Array.from(alert[field] ?? '');
    let low = 0;
    let high = characters.length;
    while (low < high) {
      const middle = Math.ceil((low + high) / 2);
      alert[field] = characters.slice(0, middle).join('');
      if (size().length <= MAX_PLAINTEXT) low = middle;
      else high = middle - 1;
    }
    alert[field] = characters.slice(0, low).join('');
  }
  if (size().length > MAX_PLAINTEXT) delete copy.options;
  if (size().length > MAX_PLAINTEXT) throw new Error('push payload exceeds relay limit');
  return size();
}

export async function sendRelay(url: string, handle: string, pushKey: string,
  payload: ApnsPayload, kind: PushKind, priority: ApnsPriority = '10'): Promise<ApnsSendResult> {
  const key = await crypto.subtle.importKey('raw', decode(pushKey), 'AES-GCM', false, ['encrypt']);
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce,
    additionalData: encoder.encode(`hiboss-push-v1|${kind}`) }, key, trimmedPayload(payload));
  const bytes = new Uint8Array(12 + encrypted.byteLength);
  bytes.set(nonce);
  bytes.set(new Uint8Array(encrypted), 12);
  const ciphertext = btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-')
    .replace(/\//g, '_').replace(/=+$/, '');
  const response = await fetch(`${url.replace(/\/$/, '')}/v1/push`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ handle, kind, ciphertext, priority: Number(priority),
      interruption: payload.aps['interruption-level'], sound: payload.aps.sound === 'default' }),
  });
  return response.ok ? { ok: true, prune: false }
    : { ok: false, prune: response.status === 410, reason: `relay ${response.status}` };
}
