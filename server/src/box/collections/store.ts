// Stores boss-owned collections and resolves readable collection filters.
// Uses scoped D1 queries; live item summaries exclude soft-deleted memberships.
import { HTTPException } from 'hono/http-exception';
import { boxBossIds } from '../access';
import type { BoxContext } from '../types';

export interface BoxCollection {
  id: string;
  boss_id: string;
  boss_name: string;
  name: string;
  item_count: number;
  cover_item_id: string | null;
  created_at: string;
  updated_at: string;
}

const SELECT = `SELECT c.*, b.name AS boss_name,
  (SELECT COUNT(*) FROM box_collection_items ci JOIN box_items i ON i.id = ci.item_id
    WHERE ci.collection_id = c.id AND i.deleted_at IS NULL) AS item_count,
  (SELECT i.id FROM box_collection_items ci JOIN box_items i ON i.id = ci.item_id
    WHERE ci.collection_id = c.id AND i.deleted_at IS NULL AND i.kind IN ('image', 'video')
    ORDER BY i.created_at DESC, i.id DESC LIMIT 1) AS cover_item_id
  FROM box_collections c JOIN bosses b ON b.id = c.boss_id`;

export async function listCollections(c: BoxContext): Promise<BoxCollection[]> {
  const bosses = await boxBossIds(c);
  if (!bosses.length) return [];
  const rows = await c.env.DB.prepare(`${SELECT}
    WHERE c.boss_id IN (${bosses.map(() => '?').join(',')}) ORDER BY b.name, c.name`)
    .bind(...bosses).all<BoxCollection>();
  return rows.results;
}

export async function resolveCollection(c: BoxContext, value: string,
  bosses: string[]): Promise<BoxCollection> {
  const rows = await c.env.DB.prepare(`${SELECT}
    WHERE c.boss_id IN (${bosses.map(() => '?').join(',')})
      AND (c.id = ? OR c.name = ? COLLATE NOCASE) ORDER BY b.name, c.name`)
    .bind(...bosses, value, value).all<BoxCollection>();
  const exact = rows.results.find(row => row.id === value);
  if (exact) return exact;
  if (!rows.results.length) throw new HTTPException(404, { message: 'not found' });
  if (rows.results.length > 1) {
    const choices = rows.results.map(row => `${row.boss_name}: ${row.name} (${row.id})`).join(', ');
    throw new HTTPException(409, { message: `choose a collection: ${choices}` });
  }
  return rows.results[0];
}

export async function findCollection(c: BoxContext, id: string): Promise<BoxCollection | null> {
  const bosses = await boxBossIds(c);
  if (!bosses.length) return null;
  return c.env.DB.prepare(`${SELECT} WHERE c.id = ?
    AND c.boss_id IN (${bosses.map(() => '?').join(',')})`)
    .bind(id, ...bosses).first<BoxCollection>();
}

export async function saveCollection(c: BoxContext, bossId: string, name: string,
  id?: string): Promise<BoxCollection> {
  const collectionId = id ?? `bc_${crypto.randomUUID().replaceAll('-', '')}`;
  const timestamp = new Date().toISOString();
  try {
    const result = id
      ? await c.env.DB.prepare(`UPDATE box_collections SET name = ?, updated_at = ?
        WHERE id = ? AND boss_id = ?`).bind(name, timestamp, id, bossId).run()
      : await c.env.DB.prepare(`INSERT INTO box_collections (id, boss_id, name, created_at, updated_at)
        SELECT ?, ?, ?, ?, ? WHERE (SELECT COUNT(*) FROM box_collections WHERE boss_id = ?) < 200`)
        .bind(collectionId, bossId, name, timestamp, timestamp, bossId).run();
    if (!result.meta.changes) throw new HTTPException(409, { message: 'collection limit reached' });
  } catch (error: unknown) {
    if (error instanceof Error && error.message.includes('UNIQUE constraint failed')) {
      throw new HTTPException(409, { message: 'collection name already exists' });
    }
    throw error;
  }
  const saved = await findCollection(c, collectionId);
  if (!saved) throw new HTTPException(404, { message: 'not found' });
  return saved;
}

export async function deleteCollection(c: BoxContext, id: string): Promise<void> {
  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM box_collection_items WHERE collection_id = ?').bind(id),
    c.env.DB.prepare('DELETE FROM box_collections WHERE id = ?').bind(id),
  ]);
}

export async function setMembership(c: BoxContext, collectionId: string, itemId: string,
  member: boolean): Promise<void> {
  const statement = member
    ? c.env.DB.prepare(`INSERT INTO box_collection_items (collection_id, item_id, added_at)
      VALUES (?, ?, ?) ON CONFLICT (collection_id, item_id) DO NOTHING`)
      .bind(collectionId, itemId, new Date().toISOString())
    : c.env.DB.prepare('DELETE FROM box_collection_items WHERE collection_id = ? AND item_id = ?')
      .bind(collectionId, itemId);
  await statement.run();
}
