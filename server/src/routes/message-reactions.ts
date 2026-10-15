// Atomic reaction storage shared by agent and boss routes.
// Preserves metadata and recognizes legacy boss identities during deduplication.
import type { Env } from '../types';

export async function storeMessageReaction(
  env: Env, messageId: string, actor: 'boss' | 'agent', actorId: string, emoji: string,
): Promise<boolean> {
  const reaction = JSON.stringify({ emoji, actor, actor_id: actorId, created_at: new Date().toISOString() });
  const row = await env.DB.prepare(`UPDATE messages SET
    metadata = json_insert(
      CASE WHEN json_type(metadata, '$.reactions') = 'array' THEN metadata
        ELSE json_set(COALESCE(metadata, '{}'), '$.reactions', json('[]')) END,
      '$.reactions[#]', json(?)), updated_at = datetime('now')
    WHERE id = ? AND NOT EXISTS (
      SELECT 1 FROM json_each(messages.metadata, '$.reactions')
      WHERE json_extract(value, '$.emoji') = ?
        AND COALESCE(json_extract(value, '$.actor'), 'boss') = ?
        AND COALESCE(json_extract(value, '$.actor_id'), json_extract(value, '$.boss_id'),
          json_extract(value, '$.user')) = ?
    ) RETURNING id`)
    .bind(reaction, messageId, emoji, actor, actorId).first<{ id: string }>();
  return row !== null;
}

export async function removeMessageReaction(
  env: Env, messageId: string, actor: 'boss' | 'agent', actorId: string, emoji: string,
): Promise<void> {
  await env.DB.prepare(`UPDATE messages SET metadata = json_set(metadata, '$.reactions', json(
    (SELECT json_group_array(json(value)) FROM json_each(messages.metadata, '$.reactions')
      WHERE NOT COALESCE(
        json_extract(value, '$.emoji') = ?
        AND COALESCE(json_extract(value, '$.actor'), 'boss') = ?
        AND COALESCE(json_extract(value, '$.actor_id'), json_extract(value, '$.boss_id'),
          json_extract(value, '$.user')) = ?, 0))
    )), updated_at = datetime('now')
    WHERE id = ? AND json_type(metadata, '$.reactions') = 'array'`)
    .bind(emoji, actor, actorId, messageId).run();
}
