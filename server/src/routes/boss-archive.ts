// Reversible boss archival with atomic last-admin protection.
// Exports archive/restore handlers; depends on boss auth, D1, and audit logging.
import type { Context } from 'hono';
import type { Env } from '../types';
import { getBossId, getBossRole } from '../middleware/auth';
import { logAudit } from '../audit';

type BossContext = Context<{ Bindings: Env }>;
type ArchiveRow = { id: string; role: string; archived_at: string | null };

export async function archiveBoss(c: BossContext): Promise<Response> {
  if (getBossRole(c) !== 'admin') return c.json({ error: 'admin required' }, 403);
  const id = c.req.param('id');
  const boss = await c.env.DB.prepare('SELECT id, role, archived_at FROM bosses WHERE id = ?').bind(id).first<ArchiveRow>();
  if (!boss) return c.text('not found', 404);
  if (boss.archived_at !== null) return c.text('boss is archived', 409);
  const liveAdmins = "SELECT COUNT(*) FROM bosses WHERE role = 'admin' AND archived_at IS NULL";
  if (boss.role === 'admin' && await c.env.DB.prepare(liveAdmins).first<number>('COUNT(*)') === 1) {
    return c.text('cannot archive the last unarchived admin', 400);
  }
  if (id === getBossId(c)) return c.text('cannot archive self', 400);
  const result = await c.env.DB.prepare(`UPDATE bosses SET archived_at = datetime('now') WHERE id = ? AND archived_at IS NULL
    AND (role != 'admin' OR (${liveAdmins}) > 1) RETURNING *`).bind(id).first();
  if (!result) {
    const current = await c.env.DB.prepare('SELECT archived_at FROM bosses WHERE id = ?').bind(id).first<Pick<ArchiveRow, 'archived_at'>>();
    if (!current) return c.text('not found', 404);
    return current.archived_at !== null ? c.text('boss is archived', 409) : c.text('cannot archive the last unarchived admin', 400);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', getBossId(c), 'boss.archive', 'boss', id));
  return c.json(result);
}

export async function restoreBoss(c: BossContext): Promise<Response> {
  if (getBossRole(c) !== 'admin') return c.json({ error: 'admin required' }, 403);
  const id = c.req.param('id');
  const result = await c.env.DB.prepare('UPDATE bosses SET archived_at = NULL WHERE id = ? AND archived_at IS NOT NULL RETURNING *').bind(id).first();
  if (!result) {
    const exists = await c.env.DB.prepare('SELECT id FROM bosses WHERE id = ?').bind(id).first();
    return exists ? c.text('boss is not archived', 409) : c.text('not found', 404);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', getBossId(c), 'boss.restore', 'boss', id));
  return c.json(result);
}
