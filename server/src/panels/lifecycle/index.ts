// Authenticated lifecycle, checkpoint, placement, and result receipt routes.
// Exports panelLifecycleRouter; all producer state changes pass through PanelRoom.
// Dependencies: Hono auth, D1 repository, and the durable lifecycle engine.

import { Hono } from 'hono';
import { dualAuth, getAgentId, getBossId, isBossAuth } from '../../middleware/auth';
import type { Env } from '../../types';
import { isRecord, type PanelContext } from '../definition/helpers';
import { authorize, readPreference, readRecord } from './repository';
import { faultResponse, PanelFault, terminal, type Lifecycle, type Preference } from './types';

const routes = new Hono<{ Bindings: Env }>();
routes.use('*', dualAuth);

async function proxy(c: PanelContext, action: string): Promise<Response> {
  try {
    const role = isBossAuth(c) ? 'subscriber' : 'producer';
    const identity = isBossAuth(c) ? getBossId(c) : getAgentId(c);
    const row = await readRecord(c.env.DB, c.req.param('id') ?? '');
    await authorize(c.env.DB, row, identity, role);
    if (!c.env.PANEL_ROOM) throw new PanelFault('service_unavailable', 503);
    const room = c.env.PANEL_ROOM.get(c.env.PANEL_ROOM.idFromName(row.target_boss_id));
    return room.fetch(new Request('https://panel-room.internal/__command', { method: 'POST', body: JSON.stringify({
      panelId: row.panel_id, identity, role, action, key: c.req.header('Idempotency-Key'), body: action === 'state' ? null : action === 'operation' ? { operationId: c.req.param('operationId') } : await c.req.json<unknown>(),
    }) }));
  } catch (error) { return faultResponse(error); }
}
routes.get('/:id/state', c => proxy(c, 'state'));
routes.post('/:id/lifecycle', c => proxy(c, 'lifecycle'));
routes.post('/:id/renew', c => proxy(c, 'renew'));
routes.put('/:id/definition', c => proxy(c, 'definition'));
routes.get('/:id/operations/:operationId', c => proxy(c, 'operation'));
routes.post('/:id/producer-lease', c => proxy(c, 'lease'));

routes.put('/:id/preferences', async c => {
  try {
    if (!isBossAuth(c)) throw new PanelFault('permission_denied', 403);
    const row = await readRecord(c.env.DB, c.req.param('id') ?? '');
    const boss = getBossId(c);
    await authorize(c.env.DB, row, boss, 'subscriber');
    const body: unknown = await c.req.json();
    if (!isRecord(body) || !Number.isInteger(body.expectedPreferenceVersion)
      || Object.keys(body).some(k => !['expectedPreferenceVersion', 'placement', 'seenTerminalVersion', 'acknowledgedTerminalVersion'].includes(k))) throw new PanelFault('invalid_preference', 422);
    const prior = await readPreference(c.env.DB, row.panel_id, boss);
    if (body.expectedPreferenceVersion !== prior.preferenceVersion) throw new PanelFault('preference_conflict');
    const next = preference(body, prior, row.metadata_version, JSON.parse(row.lifecycle_json) as Lifecycle);
    const result = await c.env.DB.prepare(`INSERT INTO panel_preferences (panel_id, boss_id, preference_version, value_json) VALUES (?, ?, ?, ?)
      ON CONFLICT(panel_id, boss_id) DO UPDATE SET preference_version = excluded.preference_version, value_json = excluded.value_json
      WHERE panel_preferences.preference_version = ?`).bind(row.panel_id, boss, next.preferenceVersion, JSON.stringify(next), prior.preferenceVersion).run();
    if (result.meta.changes !== 1) throw new PanelFault('preference_conflict');
    return c.json(next);
  } catch (error) { return faultResponse(error); }
});

function preference(body: Record<string, unknown>, prior: Preference, version: number, lifecycle: Lifecycle): Preference {
  const next = { ...prior, preferenceVersion: prior.preferenceVersion + 1 };
  if (body.placement !== undefined) {
    if (!['automatic', 'pinned', 'archived'].includes(String(body.placement))) throw new PanelFault('invalid_preference', 422);
    next.placement = body.placement as Preference['placement'];
  }
  for (const key of ['seenTerminalVersion', 'acknowledgedTerminalVersion'] as const) {
    if (body[key] === undefined) continue;
    if (!terminal(lifecycle.taskState) || body[key] !== version) throw new PanelFault('terminal_version_conflict');
    next[key] = version;
  }
  return next;
}

export const panelLifecycleRouter = routes;
