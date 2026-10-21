// D1 access for relay registrations, keyed only by SHA-256 of handle and deviceSecret.
// Lookups confirm the stored digest with a constant-time comparison.

import { constantTimeEqual, sha256Hex } from './crypto';
import type { Registration, TokenBody } from './types';

const COLUMNS = 'handle_hash, secret_hash, apns_token, environment';

export async function insertRegistration(
  db: D1Database,
  handle: string,
  secret: string,
  body: TokenBody,
  now: number,
): Promise<void> {
  await db
    .prepare(
      'INSERT INTO registrations (handle_hash, secret_hash, apns_token, environment, created_at, last_used_at) ' +
        'VALUES (?, ?, ?, ?, ?, ?)',
    )
    .bind(await sha256Hex(handle), await sha256Hex(secret), body.apnsToken, body.environment, now, now)
    .run();
}

async function findBy(
  db: D1Database,
  column: 'handle_hash' | 'secret_hash',
  value: string,
): Promise<Registration | null> {
  const digest = await sha256Hex(value);
  const row = await db
    .prepare(`SELECT ${COLUMNS} FROM registrations WHERE ${column} = ?`)
    .bind(digest)
    .first<Registration>();
  return row && constantTimeEqual(row[column], digest) ? row : null;
}

export function findByHandle(db: D1Database, handle: string): Promise<Registration | null> {
  return findBy(db, 'handle_hash', handle);
}

export function findBySecret(db: D1Database, secret: string): Promise<Registration | null> {
  return findBy(db, 'secret_hash', secret);
}

export async function updateToken(
  db: D1Database,
  handleHash: string,
  body: TokenBody,
  now: number,
): Promise<void> {
  await db
    .prepare('UPDATE registrations SET apns_token = ?, environment = ?, last_used_at = ? WHERE handle_hash = ?')
    .bind(body.apnsToken, body.environment, now, handleHash)
    .run();
}

export async function touch(db: D1Database, handleHash: string, now: number): Promise<void> {
  await db.prepare('UPDATE registrations SET last_used_at = ? WHERE handle_hash = ?').bind(now, handleHash).run();
}

export async function deleteRegistration(db: D1Database, handleHash: string): Promise<void> {
  await db.prepare('DELETE FROM registrations WHERE handle_hash = ?').bind(handleHash).run();
}
