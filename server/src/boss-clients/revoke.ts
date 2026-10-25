// Revokes boss tokens with every credential and channel derived from them, in one D1 batch.
// Exports revokeBossTokens: each token's client, signing keys, push devices and unused pairing codes retire with it.
// Depends on D1 batch transactions; the selection is a predicate over `boss_tokens t`.

export interface TokenSelection {
  readonly sql: string;
  readonly binds: readonly unknown[];
}

/** Runs `before` and the cascade atomically; returns how many live tokens were revoked. */
export async function revokeBossTokens(db: D1Database, selection: TokenSelection,
  before: readonly D1PreparedStatement[] = []): Promise<number> {
  const binds = selection.binds;
  const tokens = `SELECT t.id FROM boss_tokens t WHERE (${selection.sql}) AND t.revoked_at IS NULL`;
  const clients = `SELECT t.client_id FROM boss_tokens t
    WHERE (${selection.sql}) AND t.revoked_at IS NULL AND t.client_id IS NOT NULL`;
  const results = await db.batch([
    ...before,
    db.prepare(`DELETE FROM boss_devices WHERE token_id IN (${tokens}) OR client_id IN (${clients})`).bind(...binds, ...binds),
    db.prepare(`DELETE FROM boss_pairing_codes WHERE consumed_at IS NULL AND issued_by_token_id IN (${tokens})`).bind(...binds),
    db.prepare(`UPDATE boss_signing_keys SET revoked_at = COALESCE(revoked_at, datetime('now'))
      WHERE boss_token_id IN (${tokens}) OR client_id IN (${clients})`).bind(...binds, ...binds),
    db.prepare(`UPDATE boss_clients SET revoked_at = COALESCE(revoked_at, datetime('now')) WHERE id IN (${clients})`).bind(...binds),
    db.prepare(`UPDATE boss_tokens SET revoked_at = datetime('now') WHERE id IN (${tokens})`).bind(...binds),
  ]);
  return results[results.length - 1].meta.changes ?? 0;
}
