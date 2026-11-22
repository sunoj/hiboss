// Resolves a full id or an id prefix with one primary-key range seek; `LIKE 'p%'` scans the table.
// Exports idPrefixRange and findMessageByIdPrefix; depends only on D1 and the message row type.
// Ids are ASCII, so JavaScript code-unit order matches SQLite's BINARY (UTF-8 byte) order.
import type { MessageRow } from '../types';

/** Half-open bounds of every id that starts with `prefix`; the exact id sorts first. */
export function idPrefixRange(prefix: string): [string, string] {
  if (prefix === '') return ['', ''];
  const last = prefix.charCodeAt(prefix.length - 1);
  return [prefix, `${prefix.slice(0, -1)}${String.fromCharCode(last + 1)}`];
}

const WITH_AGENT_NAME = 'SELECT messages.*, api_keys.name AS agent_name FROM messages '
  + 'LEFT JOIN api_keys ON api_keys.id = messages.agent_id';

/**
 * The message whose id is `id`, else the lowest id starting with `id`. Callers check access.
 * Message ids are lowercase hex, so input is lowercased like the case-insensitive LIKE it replaced.
 */
export function findMessageByIdPrefix(db: D1Database, id: string, withAgentName = false): Promise<MessageRow | null> {
  const [low, high] = idPrefixRange(id.toLowerCase());
  const select = withAgentName ? WITH_AGENT_NAME : 'SELECT messages.* FROM messages';
  return db.prepare(`${select} WHERE messages.id >= ? AND messages.id < ? ORDER BY messages.id LIMIT 1`)
    .bind(low, high).first<MessageRow>();
}
