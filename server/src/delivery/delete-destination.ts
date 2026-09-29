// Promotes merged delivery claims before their primary destination is deleted.
// Exports D1 statements for callers to batch atomically with destination removal.
// Depends on the message_deliveries self-reference and D1 prepared statements.
import type { Env } from '../types';

interface PrimaryDelivery {
  id: string;
  external_target: string | null;
  next_attempt_at: string | null;
  status: string;
  attempts: number;
  external_message_id: string | null;
  last_error: string | null;
  successor: string | null;
}

export async function preserveMergedDeliveries(
  env: Env, destinationId: string, removingIds: string[] = [destinationId],
): Promise<D1PreparedStatement[]> {
  const placeholders = removingIds.map(() => '?').join(', ');
  const primaries = await env.DB.prepare(`SELECT p.id, p.external_target, p.next_attempt_at,
    p.status, p.attempts, p.external_message_id, p.last_error,
    (SELECT child.id FROM message_deliveries child WHERE child.merged_into = p.id
      AND child.destination_id NOT IN (${placeholders}) ORDER BY child.id LIMIT 1) AS successor
    FROM message_deliveries p WHERE p.destination_id = ?`).bind(...removingIds, destinationId).all<PrimaryDelivery>();
  const statements: D1PreparedStatement[] = [];
  for (const row of primaries.results) {
    if (!row.successor) continue;
    statements.push(env.DB.prepare('UPDATE message_deliveries SET external_target = NULL WHERE id = ?').bind(row.id));
    statements.push(env.DB.prepare(`UPDATE message_deliveries SET merged_into = NULL, external_target = ?,
      next_attempt_at = ?, status = ?, attempts = ?, external_message_id = ?, last_error = ?, updated_at = datetime('now')
      WHERE id = ? AND merged_into = ?`).bind(row.external_target, row.next_attempt_at, row.status,
        row.attempts, row.external_message_id, row.last_error, row.successor, row.id));
    statements.push(env.DB.prepare('UPDATE message_deliveries SET merged_into = ? WHERE merged_into = ?')
      .bind(row.successor, row.id));
  }
  return statements;
}
