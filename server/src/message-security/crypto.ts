// P-256 helpers for pairing proof verification and strict base64url handling.
// Exports signing-registration parsing, verification, and stable key IDs.
// Depends on Web Crypto and message-security domain types.

import type { RegisteredSigningKey, SigningKeyId, SigningRegistration } from './types';

const PAIRING_DOMAIN = 'hiboss-pair-v1';
const P256_PUBLIC_KEY_BYTES = 65;
const ES256_SIGNATURE_BYTES = 64;

export function parseSigningRegistration(value: unknown): SigningRegistration | null {
  if (value === undefined) return null;
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  const algorithm = record['algorithm'];
  const clientKind = record['client_kind'];
  const publicKey = record['public_key'];
  const proof = record['proof'];
  if (algorithm !== 'ES256' || (clientKind !== 'ios' && clientKind !== 'macos')) return null;
  if (typeof publicKey !== 'string' || typeof proof !== 'string') return null;
  if (!publicKey || !proof) return null;
  return { algorithm, clientKind, publicKey, proof };
}

export async function verifyPairingRegistration(
  code: string,
  registration: SigningRegistration,
): Promise<RegisteredSigningKey | null> {
  const publicKey = decodeBase64Url(registration.publicKey);
  const proof = decodeBase64Url(registration.proof);
  if (!publicKey || publicKey.length !== P256_PUBLIC_KEY_BYTES) return null;
  if (!proof || proof.length !== ES256_SIGNATURE_BYTES) return null;
  const input = new TextEncoder().encode(
    `${PAIRING_DOMAIN}\n${code}\n${registration.clientKind}\n${registration.publicKey}`,
  );
  if (!(await verifyEs256(publicKey, proof, input))) return null;
  const id = await deriveSigningKeyId(publicKey);
  return { ...registration, id };
}

export async function verifyEs256(
  publicKey: Uint8Array,
  signature: Uint8Array,
  input: Uint8Array,
): Promise<boolean> {
  try {
    const key = await crypto.subtle.importKey(
      'raw', toArrayBuffer(publicKey), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify'],
    );
    return crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' }, key,
      toArrayBuffer(signature), toArrayBuffer(input),
    );
  } catch {
    return false;
  }
}

export function decodeBase64Url(value: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) return null;
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padding = '='.repeat((4 - normalized.length % 4) % 4);
  try {
    const binary = atob(normalized + padding);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
}

async function deriveSigningKeyId(publicKey: Uint8Array): Promise<SigningKeyId> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', toArrayBuffer(publicKey)));
  let binary = '';
  for (const byte of digest) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_') as SigningKeyId;
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.slice().buffer as ArrayBuffer;
}
