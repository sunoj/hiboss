// Self-verifying push handles: base64url(id(16 random bytes) || HMAC-SHA256(HANDLE_KEY, id)[0..16]).
// A handle whose MAC fails is rejected without any D1 access. Only canonical encodings verify.
// Depends on Workers WebCrypto and the HANDLE_KEY Worker secret.

import { base64UrlBytes } from './crypto';

const ID_BYTES = 16;
const MAC_BYTES = 16;
const HANDLE = /^[A-Za-z0-9_-]{43}$/;

async function mac(secret: string, id: Uint8Array): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, id)).slice(0, MAC_BYTES);
}

function decode(handle: string): Uint8Array | null {
  if (!HANDLE.test(handle)) return null;
  const binary = atob(handle.replace(/-/g, '+').replace(/_/g, '/') + '=');
  const bytes = Uint8Array.from(binary, (ch) => ch.charCodeAt(0));
  return base64UrlBytes(bytes) === handle ? bytes : null;
}

export async function mintHandle(secret: string): Promise<string> {
  const id = crypto.getRandomValues(new Uint8Array(ID_BYTES));
  const bytes = new Uint8Array(ID_BYTES + MAC_BYTES);
  bytes.set(id);
  bytes.set(await mac(secret, id), ID_BYTES);
  return base64UrlBytes(bytes);
}

/** True only for a canonical handle whose MAC matches, compared without an early exit. */
export async function handleValid(secret: string, handle: string): Promise<boolean> {
  const bytes = decode(handle);
  if (!bytes) return false;
  const expected = await mac(secret, bytes.slice(0, ID_BYTES));
  let diff = 0;
  for (let i = 0; i < MAC_BYTES; i += 1) diff |= expected[i] ^ bytes[ID_BYTES + i];
  return diff === 0;
}
