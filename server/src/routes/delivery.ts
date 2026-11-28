// Records operational failures when the app-only delivery queue drains.
// Depends on the shared message metadata and status SQL.
import { MESSAGE_METADATA_OBJECT_SQL } from './message-reactions';
import type { Env } from '../types';

export function getDeliveryErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'delivery failure';
}

export async function persistDeliveryFailure(env: Env, messageId: string, errorMessage: string): Promise<void> {
  await env.DB.prepare(
    `UPDATE messages SET metadata = json_set(${MESSAGE_METADATA_OBJECT_SQL}, '$.delivery_error', ?),
      updated_at = datetime('now') WHERE id = ?`
  ).bind(errorMessage, messageId).run();
}
