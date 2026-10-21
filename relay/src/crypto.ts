// Capability minting, hashing and constant-time comparison for the relay.
// Depends on Workers WebCrypto (getRandomValues, digest).

const encoder = new TextEncoder();

export function base64UrlBytes(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

/** 32 CSPRNG bytes as unpadded base64url (43 characters). */
export function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64UrlBytes(bytes);
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value)));
  return Array.from(digest, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** Compares two digests without an early exit on the first differing byte. */
export function constantTimeEqual(a: string, b: string): boolean {
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  if (left.byteLength !== right.byteLength) return false;
  let diff = 0;
  for (let i = 0; i < left.byteLength; i += 1) {
    diff |= left[i] ^ right[i];
  }
  return diff === 0;
}
