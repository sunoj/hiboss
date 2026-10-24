// Persists scoped Box items and serializes idempotent creation in D1 batches.
// Exports row loading, creation, editable fields, thumbnails and soft/purge deletion.
import type { Blob as R2Blob } from '@cloudflare/workers-types';
import { boxBossIds } from './access';
import type {
  BoxContext, BoxRow, BoxThumbnail, BoxUpload, BoxMetadata, BoxWriteScope,
} from './types';

export const BOX_SELECT = `SELECT i.*, b.name AS boss_name, a.name AS agent_name,
  (SELECT json_group_array(collection_id) FROM
    (SELECT collection_id FROM box_collection_items WHERE item_id = i.id
      ORDER BY added_at, collection_id)) AS collection_ids FROM box_items i `
  + 'JOIN bosses b ON b.id = i.boss_id LEFT JOIN api_keys a ON a.id = i.agent_id';

function idempotencyScope(scope: BoxWriteScope): {
  table: 'box_agent_idempotency' | 'box_idempotency';
  columns: string;
  predicate: string;
  binds: string[];
} {
  const agent = scope.agentId !== null;
  return {
    table: agent ? 'box_agent_idempotency' : 'box_idempotency',
    columns: agent ? 'boss_id, agent_id, idempotency_key' : 'boss_id, idempotency_key',
    predicate: agent ? 'boss_id = ? AND agent_id = ? AND idempotency_key = ?'
      : 'boss_id = ? AND idempotency_key = ?',
    binds: scope.agentId === null ? [scope.bossId] : [scope.bossId, scope.agentId],
  };
}

export async function findItem(c: BoxContext, id: string, includeDeleted = false): Promise<BoxRow | null> {
  const ids = await boxBossIds(c);
  if (!ids.length) return null;
  return c.env.DB.prepare(`${BOX_SELECT} WHERE i.id = ? AND i.boss_id IN
    (${ids.map(() => '?').join(',')}) ${includeDeleted ? '' : 'AND i.deleted_at IS NULL'}`)
    .bind(id, ...ids).first<BoxRow>();
}

export async function replayItem(c: BoxContext, scope: BoxWriteScope,
  key: string): Promise<BoxRow | null | undefined> {
  const retry = idempotencyScope(scope);
  const record = await c.env.DB.prepare(`SELECT item_id FROM ${retry.table}
    WHERE ${retry.predicate}`).bind(...retry.binds, key).first<{ item_id: string }>();
  return record ? findItem(c, record.item_id) : undefined;
}

export function thumbKey(bossId: string, itemId: string): string {
  return `box/${bossId}/${itemId}.thumb`;
}

function insertItem(c: BoxContext, scope: BoxWriteScope, upload: BoxUpload, id: string,
  mediaKey: string | null, key: string | undefined): ReturnType<BoxContext['env']['DB']['prepare']> {
  const { meta, file, kind, thumbnail } = upload;
  const retry = idempotencyScope(scope);
  const source = scope.agentId === null ? meta.source : 'cli';
  const binds: (string | number | null)[] = [id, scope.bossId, kind, meta.text, meta.url, meta.note,
    mediaKey, file ? file.type || 'application/octet-stream' : null, file?.size ?? null,
    file ? meta.width : null, file ? meta.height : null, file ? meta.duration_ms : null,
    meta.project, JSON.stringify(meta.tags), source, new Date().toISOString(), scope.agentId,
    thumbnail ? thumbKey(scope.bossId, id) : null, thumbnail?.bytes.length ?? null];
  const guard = key ? ` WHERE NOT EXISTS (SELECT 1 FROM ${retry.table} WHERE ${retry.predicate})` : '';
  if (key) binds.push(...retry.binds, key);
  return c.env.DB.prepare(`INSERT INTO box_items
    (id, boss_id, kind, text, url, note, media_key, media_type, media_bytes, width, height,
      duration_ms, project, tags, source, created_at, agent_id, thumb_key, thumb_bytes)
    SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?${guard}`).bind(...binds);
}

async function putObjects(c: BoxContext, scope: BoxWriteScope, upload: BoxUpload,
  id: string): Promise<string[]> {
  const keys: string[] = [];
  try {
    if (upload.file) {
      keys.push(`box/${scope.bossId}/${id}`);
      await c.env.ATTACHMENTS.put(keys[0], upload.file as unknown as R2Blob, {
        httpMetadata: { contentType: upload.file.type || 'application/octet-stream' },
        customMetadata: { filename: upload.file.name, boss_id: scope.bossId },
      });
    }
    if (upload.thumbnail) {
      keys.push(thumbKey(scope.bossId, id));
      await putThumbnailObject(c, keys[keys.length - 1], scope.bossId, upload.thumbnail);
    }
    return keys;
  } catch (error: unknown) {
    if (keys.length) await c.env.ATTACHMENTS.delete(keys);
    throw error;
  }
}

function putThumbnailObject(c: BoxContext, key: string, bossId: string,
  thumbnail: BoxThumbnail): Promise<unknown> {
  return c.env.ATTACHMENTS.put(key, thumbnail.bytes, {
    httpMetadata: { contentType: thumbnail.type }, customMetadata: { boss_id: bossId },
  });
}

export async function createItem(c: BoxContext, scope: BoxWriteScope, upload: BoxUpload,
  key: string | undefined): Promise<BoxRow | null> {
  const id = `bx_${crypto.randomUUID().replaceAll('-', '')}`;
  const objects = await putObjects(c, scope, upload, id);
  try {
    const statements = [insertItem(c, scope, upload, id, upload.file ? objects[0] : null, key)];
    const retry = idempotencyScope(scope);
    if (key) statements.push(c.env.DB.prepare(`INSERT INTO ${retry.table}
      (${retry.columns}, item_id) VALUES (${retry.binds.map(() => '?').join(', ')}, ?, ?)
      ON CONFLICT (${retry.columns}) DO NOTHING`).bind(...retry.binds, key, id));
    await c.env.DB.batch(statements);
    const row = key ? await replayItem(c, scope, key) : await findItem(c, id);
    if (objects.length && row?.id !== id) await c.env.ATTACHMENTS.delete(objects);
    return row ?? null;
  } catch (error: unknown) {
    if (objects.length) await c.env.ATTACHMENTS.delete(objects);
    throw error;
  }
}

export async function storeThumbnail(c: BoxContext, row: BoxRow,
  thumbnail: BoxThumbnail): Promise<BoxRow | null> {
  const key = thumbKey(row.boss_id, row.id);
  await putThumbnailObject(c, key, row.boss_id, thumbnail);
  try {
    const result = await c.env.DB.prepare(`UPDATE box_items SET thumb_key = ?, thumb_bytes = ?
      WHERE id = ? AND boss_id = ? AND deleted_at IS NULL`)
      .bind(key, thumbnail.bytes.length, row.id, row.boss_id).run();
    if (!result.meta.changes && row.thumb_key === null) await c.env.ATTACHMENTS.delete(key);
  } catch (error: unknown) {
    if (row.thumb_key === null) await c.env.ATTACHMENTS.delete(key);
    throw error;
  }
  return findItem(c, row.id);
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
    const keys = [row.media_key, row.thumb_key].filter((key): key is string => key !== null);
    if (keys.length) await c.env.ATTACHMENTS.delete(keys);
    await c.env.DB.batch([
      c.env.DB.prepare('DELETE FROM box_collection_items WHERE item_id = ?').bind(row.id),
      c.env.DB.prepare('DELETE FROM box_items WHERE id = ? AND boss_id = ?')
        .bind(row.id, row.boss_id),
    ]);
    return;
  }
  await c.env.DB.prepare('UPDATE box_items SET deleted_at = ? WHERE id = ? AND boss_id = ?')
    .bind(new Date().toISOString(), row.id, row.boss_id).run();
}

export async function likeItem(c: BoxContext, row: BoxRow, liked: boolean): Promise<BoxRow | null> {
  await c.env.DB.prepare(`UPDATE box_items SET liked_at = ${liked ? 'COALESCE(liked_at, ?)' : 'NULL'}
    WHERE id = ? AND boss_id = ? AND deleted_at IS NULL`)
    .bind(...(liked ? [new Date().toISOString()] : []), row.id, row.boss_id).run();
  return findItem(c, row.id);
}
