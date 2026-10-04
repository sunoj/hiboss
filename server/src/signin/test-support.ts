// Shared request helpers for the "Sign in with iPhone" tests: the Mac side (open, poll,
// complete) and the iPhone side (view, approve, reject), plus a signing proof builder.
// Depends on cloudflare:test SELF.

import { SELF } from 'cloudflare:test';

export interface Opened { request_id: string; poll_token: string; expires_at: string }

const JSON_HEADERS = { 'Content-Type': 'application/json' };
const encoder = new TextEncoder();

export function boss(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}`, ...JSON_HEADERS };
}

export async function open(label = 'Studio Mac'): Promise<Opened> {
  const res = await SELF.fetch('http://localhost/api/signin/requests', {
    method: 'POST', headers: JSON_HEADERS, body: JSON.stringify({ device_label: label }),
  });
  if (res.status !== 201) throw new Error(`open failed: ${res.status}`);
  return res.json() as Promise<Opened>;
}

export async function status(pollToken: string): Promise<Response> {
  return SELF.fetch('http://localhost/api/signin/status', { headers: { 'X-Signin-Token': pollToken } });
}

export async function complete(pollToken: string, body: Record<string, unknown>): Promise<Response> {
  return SELF.fetch('http://localhost/api/signin/complete', {
    method: 'POST', headers: { 'X-Signin-Token': pollToken, ...JSON_HEADERS }, body: JSON.stringify(body),
  });
}

export async function view(id: string, token: string): Promise<Response> {
  return SELF.fetch(`http://localhost/api/boss/signin-requests/${id}`, { headers: boss(token) });
}

export async function act(id: string, action: 'approve' | 'reject', token: string): Promise<Response> {
  return SELF.fetch(`http://localhost/api/boss/signin-requests/${id}/${action}`, { method: 'POST', headers: boss(token) });
}

export async function approvedCode(id: string, token: string): Promise<string> {
  const res = await act(id, 'approve', token);
  if (res.status !== 200) throw new Error(`approve failed: ${res.status}`);
  return ((await res.json()) as { code: string }).code;
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

/** A signing registration whose proof signs `domain\nsubject\nmacos\npublicKey`. */
export async function registration(domain: string, subject: string): Promise<Record<string, string>> {
  const keys = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign', 'verify']);
  const publicKey = base64Url(new Uint8Array(await crypto.subtle.exportKey('raw', keys.publicKey) as ArrayBuffer));
  const input = encoder.encode(`${domain}\n${subject}\nmacos\n${publicKey}`);
  const proof = base64Url(new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, keys.privateKey, input.buffer as ArrayBuffer)));
  return { algorithm: 'ES256', client_kind: 'macos', public_key: publicKey, proof };
}
