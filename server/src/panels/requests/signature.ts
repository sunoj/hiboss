// Authenticates questionnaire-specific ES256 payloads without unsigned downgrades.
// Exports authenticateSubmission with server-owned answer provenance.
// Dependencies: existing key registry, crypto helpers, and semantic JSON hashing.

import { decodeBase64Url, verifyEs256 } from '../../message-security/crypto';
import { bearerApiMetadata, signedApiMetadata } from '../../message-security/provenance';
import type { StoredSigningKey } from '../../message-security/types';
import { bodyHash, isRecord } from '../definition/helpers';
import { PanelFault } from '../lifecycle/types';
import type { Submission } from './types';

export interface Submitter { bossId: string; bossName: string; tokenId: string; }
const MAX_SKEW_SECONDS = 300;

export async function authenticateSubmission(db: D1Database, actor: Submitter, submission: Submission, signed: unknown): Promise<Record<string, unknown>> {
  const key = await db.prepare('SELECT * FROM boss_signing_keys WHERE boss_token_id = ?').bind(actor.tokenId).first<StoredSigningKey & { revoked_at: string | null }>();
  if (key?.revoked_at) throw new PanelFault('signing_key_revoked', 403);
  const boss = { id: actor.bossId, name: actor.bossName };
  if (!key) {
    if (signed !== undefined) throw new PanelFault('signing_key_not_registered', 403);
    return bearerApiMetadata(boss, actor.tokenId);
  }
  if (key.boss_id !== actor.bossId || typeof signed !== 'string') throw new PanelFault('signature_required', 403);
  const parts = signed.split('.');
  if (parts.length !== 3) throw new PanelFault('invalid_signature', 403);
  const [headerData, payloadData, signatureData] = parts.map(decodeBase64Url);
  const publicKey = decodeBase64Url(key.public_key);
  if (!headerData || !payloadData || !signatureData || !publicKey) throw new PanelFault('invalid_signature', 403);
  let header: unknown, payload: unknown;
  try { header = JSON.parse(new TextDecoder().decode(headerData)); payload = JSON.parse(new TextDecoder().decode(payloadData)); }
  catch { throw new PanelFault('invalid_signature', 403); }
  if (!isRecord(header) || header.alg !== 'ES256' || header.kid !== key.id || header.typ !== 'hiboss-interaction+jws' || header.crit !== undefined
    || !isRecord(payload) || !Number.isSafeInteger(payload.issuedAt)
    || Math.abs(Date.now() / 1000 - Number(payload.issuedAt)) > MAX_SKEW_SECONDS) throw new PanelFault('invalid_signature', 403);
  const { issuedAt: _, ...semantic } = payload;
  if (await bodyHash(semantic) !== await bodyHash(submission)
    || !await verifyEs256(publicKey, signatureData, new TextEncoder().encode(`${parts[0]}.${parts[1]}`))) throw new PanelFault('invalid_signature', 403);
  return signedApiMetadata(boss, actor.tokenId, key, signed);
}
