// Invalidates questionnaire discovery after a committed mutation or safe retry.
// Exports notifyRequestWall; dependencies: authoritative panel records and notifyWall.

import type { Env } from '../../types';
import { readRecord } from '../lifecycle/repository';
import type { Lifecycle } from '../lifecycle/types';
import { notifyWall } from '../relay/wall';

export async function notifyRequestWall(env: Env, panelId: string): Promise<void> {
  try {
    const panel = await readRecord(env.DB, panelId);
    const lifecycle = JSON.parse(panel.lifecycle_json) as Lifecycle;
    if (!lifecycle.expiresAt) throw new Error('Missing panel expiry');
    await notifyWall(env, panel.target_boss_id, panel.panel_id, panel.agent_id, lifecycle.expiresAt);
  } catch {
    // The mutation is committed; as with panel publication, reconciliation recovers a lost signal.
  }
}
