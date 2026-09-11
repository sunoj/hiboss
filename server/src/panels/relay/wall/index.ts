// Issues identity-scoped wall tickets and forwards committed publication signals.
// Exports wall routes and notifyWall; dependencies: existing auth and PanelRoom.

import { bossCanAccessAgent } from '../../access';
import { Hono } from 'hono';
import { dualAuth, getAgentId, getBossId, isBossAuth } from '../../../middleware/auth';
import type { Env } from '../../../types';
import { isRecord } from '../ticket';

export const panelWallRouter = new Hono<{ Bindings: Env }>();

panelWallRouter.post('/panel-wall-connections', dualAuth, async c => {
  const body: unknown = await c.req.json().catch(() => null);
  if (!isRecord(body)) return c.json({ error: 'invalid_request' }, 400);
  const boss = isBossAuth(c);
  const identity = boss ? getBossId(c) : getAgentId(c);
  const roomId = boss ? identity : body.targetBossId;
  if (typeof roomId !== 'string' || !roomId) return c.json({ error: 'invalid_request' }, 400);
  if (boss && body.targetBossId !== undefined && body.targetBossId !== identity) return c.json({ error: 'permission_denied' }, 403);
  if (!boss) {
    const access = await bossCanAccessAgent(c.env.DB, roomId, identity);
    if (!access) return c.json({ error: 'permission_denied' }, 403);
  }
  if (!c.env.PANEL_ROOM) return c.json({ error: 'service_unavailable' }, 503);
  const room = c.env.PANEL_ROOM.get(c.env.PANEL_ROOM.idFromName(roomId));
  const response = await room.fetch(new Request('https://panel-room.internal/__issue-ticket', {
    method: 'POST', body: JSON.stringify({ roomId, identity, role: boss ? 'subscriber' : 'producer',
      panelId: 'wall', operations: ['wall.subscribe'], expiresAt: Date.now() + 60_000 }),
  }));
  if (!response.ok) return c.json({ error: 'service_unavailable' }, 503);
  return c.json(await response.json(), 201);
});

export async function notifyWall(env: Env, bossId: string, panelId: string, agentId: string, expiresAt: string): Promise<void> {
  if (!env.PANEL_ROOM) return;
  const room = env.PANEL_ROOM.get(env.PANEL_ROOM.idFromName(bossId));
  const response = await room.fetch(new Request('https://panel-room.internal/__wall-changed', {
    method: 'POST', body: JSON.stringify({ panelId, agentId, expiresAt }),
  }));
  if (!response.ok) throw new Error('Wall signal unavailable');
}
