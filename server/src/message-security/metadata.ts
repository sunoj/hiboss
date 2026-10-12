// Removes server-owned keys from client-supplied message metadata before storage.
// Exports stripServerOwnedMetadata; pure, no dependencies.
// Provenance, delivery and resolution state are written only by the server.

const SERVER_OWNED_KEYS = new Set([
  'provenance', 'source', 'boss_id', 'boss_name', 'auto_default', 'ask_deadline',
  'options', 'file_url', 'options_resolved', 'options_expired', 'selected_option', 'reactions',
  'telegram_message_id', 'telegram_chat_id', 'discord_message_id', 'delivery_results', 'delivery_error',
]);

/** Returns a copy without server-owned keys; null when nothing client-owned remains. */
export function stripServerOwnedMetadata(value: Record<string, unknown> | null): Record<string, unknown> | null {
  if (!value) return null;
  const kept = Object.fromEntries(Object.entries(value).filter(([key]) => !SERVER_OWNED_KEYS.has(key)));
  return Object.keys(kept).length > 0 ? kept : null;
}
