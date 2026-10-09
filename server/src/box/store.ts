// Persists scoped Box items and serializes idempotent creation in D1 batches.
// Exports row loading, creation, editable fields and soft/purge deletion.
import type { Blob as R2Blob } from '@cloudflare/workers-types';
import { boxBossIds } from './access';
import type { BoxContext, BoxRow, BoxUpload, BoxMetadata, BoxWriteScope } from './types';

export const BOX_SELECT = 'SELECT i.*, b.name AS boss_name, a.name AS agent_name FROM box_items i '
  + 'JOIN bosses b ON b.id = i.boss_id LEFT JOIN api_keys a ON a.id = i.agent_id';

export async function findItem(c: BoxContext, id: string, includeDeleted = false): Promise<BoxRow | null> {
  const ids = await boxBossIds(c);
  if (!ids.length) return null;
  return c.env.DB.prepare(`${BOX_SELECT} WHERE i.id = ? AND i.boss_id IN
    (${ids.map(() => '?').join(',')}) ${includeDeleted ? '' : 'AND i.deleted_at IS NULL'}`)
    .bind(id, ...ids).first<BoxRow>();
}

export async function replayItem(c: BoxContext, scope: BoxWriteScope,
  key: string): Promise<BoxRow | null | undefined> {
  const record = await c.env.DB.prepare(`SELECT item_id FROM box_idempotency
    WHERE boss_id = ? AND author = ? AND idempotency_key = ?`)
    .bind(scope.bossId, scope.agentId ?? '', key).first<{ item_id: string }>();
  return record ? findItem(c, record.item_id) : undefined;
}

function insertItem(c: BoxContext, scope: BoxWriteScope, upload: BoxUpload, id: string,
  mediaKey: string | null, key: string | undefined): ReturnType<BoxContext['env']['DB']['prepare']> {
  const { meta, file, kind } = upload;
  const binds: (string | number | null)[] = [id, scope.bossId, kind, meta.text, meta.url, meta.note,
    mediaKey, file ? file.type || 'application/octet-stream' : null, file?.size ?? null,
    file ? meta.width : null, file ? meta.height : null, file ? meta.duration_ms : null,
    meta.project, JSON.stringify(meta.tags), meta.source, new Date().toISOString(), scope.agentId];
  const guard = key ? ' WHERE NOT EXISTS (SELECT 1 FROM box_idempotency '
    + 'WHERE boss_id = ? AND author = ? AND idempotency_key = ?)' : '';
  if (key) binds.push(scope.bossId, scope.agentId ?? '', key);
  return c.env.DB.prepare(`INSERT INTO box_items
    (id, boss_id, kind, text, url, note, media_key, media_type, media_bytes, width, height,
      duration_ms, project, tags, source, created_at, agent_id)
    SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?${guard}`).bind(...binds);
}

export async function createItem(c: BoxContext, scope: BoxWriteScope, upload: BoxUpload,
  key: string | undefined): Promise<BoxRow | null> {
  const id = `bx_${crypto.randomUUID().replaceAll('-', '')}`;
  const mediaKey = upload.file ? `box/${scope.bossId}/${id}` : null;
  if (upload.file && mediaKey) {
    await c.env.ATTACHMENTS.put(mediaKey, upload.file as unknown as R2Blob, {
      httpMetadata: { contentType: upload.file.type || 'application/octet-stream' },
      customMetadata: { filename: upload.file.name, boss_id: scope.bossId },
    });
  }
  try {
    const statements = [insertItem(c, scope, upload, id, mediaKey, key)];
    if (key) statements.push(c.env.DB.prepare(`INSERT INTO box_idempotency
      (boss_id, author, idempotency_key, item_id) VALUES (?, ?, ?, ?)
      ON CONFLICT (boss_id, author, idempotency_key) DO NOTHING`)
      .bind(scope.bossId, scope.agentId ?? '', key, id));
    await c.env.DB.batch(statements);
    const row = key ? await replayItem(c, scope, key) : await findItem(c, id);
    if (mediaKey && row?.id !== id) await c.env.ATTACHMENTS.delete(mediaKey);
    return row ?? null;
  } catch (error: unknown) {
    if (mediaKey) await c.env.ATTACHMENTS.delete(mediaKey);
    throw error;
  }
}

export async function updateItem(c: BoxContext, row: BoxRow,
  patch: Partial<Pick<BoxMetadata, 'note' | 'project' | 'tags'>>): Promise<BoxRow | null> {
  await c.env.DB.prepare(`UPDATE box_items SET note = ?, project = ?, tags = ?
    WHERE id = ? AND boss_id = ? AND deleted_at IS NULL`).bind(
    patch.note === undefined ? row.note : patch.note,
    patch.project === undefined ? row.project : patch.project,
    patch.tags === undefined ? row.tags : JSON.stringify(patch.tags), row.id, row.boss_id,
  ).run();
  return findItem(c, row.id);
}

export async function deleteItem(c: BoxContext, row: BoxRow, purge: boolean): Promise<void> {
  if (purge) {
    if (row.media_key) await c.env.ATTACHMENTS.delete(row.media_key);
    await c.env.DB.prepare('DELETE FROM box_items WHERE id = ? AND boss_id = ?')
      .bind(row.id, row.boss_id).run();
    return;
  }
  await c.env.DB.prepare('UPDATE box_items SET deleted_at = ? WHERE id = ? AND boss_id = ?')
    .bind(new Date().toISOString(), row.id, row.boss_id).run();
}
