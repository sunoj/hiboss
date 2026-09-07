// HTTP connection-ticket issuance and credential-free relay upgrade routes.
// Exports panelRelayRouter for authenticated ticket creation and ticket handoff.
// Dependencies: Hono, existing API-key auth, D1 panels, and PanelRoom.

import { Context, Hono } from 'hono';
import { dualAuth, getAgentId, getBossId, isBossAuth } from '../../middleware/auth';
import type { Env } from '../../types';
import {
  decodeTicketEnvelope,
  isPanelRole,
  isRecord,
  type PanelOperation,
  type PanelRole,
} from './ticket';

const TICKET_LIFETIME_MS = 60_000;

type RelayContext = Context<{ Bindings: Env }>;

interface PanelScopeRow {
  readonly target_boss_id: string;
}

function errorResponse(c: RelayContext, status: 400 | 403 | 404 | 503, code: string, message: string): Response {
  return c.json({ error: { code, message, retryable: false } }, status);
}

function operationsFor(role: PanelRole): readonly PanelOperation[] {
  return role === 'producer' ? ['subscribe', 'lease.claim', 'state.update'] : ['subscribe'];
}

async function requestBody(c: RelayContext): Promise<Record<string, unknown> | null> {
  try {
    const value = await c.req.json<unknown>();
    return isRecord(value) ? value : null;
  } catch {
    return null;
  }
}

async function panelScope(c: RelayContext, panelId: string, role: PanelRole, identity: string): Promise<PanelScopeRow | null> {
  if (role === 'producer') {
    return c.env.DB.prepare('SELECT target_boss_id FROM panels WHERE panel_id = ? AND agent_id = ? LIMIT 1')
      .bind(panelId, identity).first<PanelScopeRow>();
  }
  return c.env.DB.prepare(
    'SELECT p.target_boss_id FROM panels p JOIN boss_agent_access ba ON ba.agent_id = p.agent_id AND ba.boss_id = ? WHERE p.panel_id = ? AND p.target_boss_id = ? LIMIT 1',
  ).bind(identity, panelId, identity).first<PanelScopeRow>();
}

async function issueConnectionTicket(c: RelayContext): Promise<Response> {
  const body = await requestBody(c);
  const panelId = typeof body?.panelId === 'string' ? body.panelId.trim() : '';
  const role = body?.role;
  if (!panelId || !isPanelRole(role)) return errorResponse(c, 400, 'invalid_request', 'panelId and role are required');
  const expectedRole: PanelRole = isBossAuth(c) ? 'subscriber' : 'producer';
  if (role !== expectedRole) return errorResponse(c, 403, 'permission_denied', 'The authenticated caller cannot request this role');
  const identity = isBossAuth(c) ? getBossId(c) : getAgentId(c);
  const panel = await panelScope(c, panelId, role, identity);
  if (!panel) return errorResponse(c, 404, 'not_found', 'Panel was not found');
  if (!c.env.PANEL_ROOM) return errorResponse(c, 503, 'service_unavailable', 'Panel relay is unavailable');
  const expiresAt = Date.now() + TICKET_LIFETIME_MS;
  const roomId = panel.target_boss_id;
  const operations = operationsFor(role);
  const room = c.env.PANEL_ROOM.get(c.env.PANEL_ROOM.idFromName(roomId));
  const response = await room.fetch(new Request('https://panel-room.internal/__issue-ticket', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ roomId, identity, role, panelId, operations, expiresAt }),
  }));
  if (!response.ok) return errorResponse(c, 503, 'service_unavailable', 'Panel relay could not issue a ticket');
  const issued = await response.json<unknown>();
  return c.json(issued, 201);
}

async function upgradeRelay(c: RelayContext): Promise<Response> {
  if (c.req.header('Upgrade')?.toLowerCase() !== 'websocket') return c.text('Expected Upgrade: websocket', 426);
  const rawTicket = c.req.header('X-Panel-Connection-Ticket');
  if (!rawTicket || !c.env.PANEL_ROOM) return c.text('Invalid ticket', 401);
  const envelope = decodeTicketEnvelope(rawTicket);
  if (!envelope) return c.text('Invalid ticket', 401);
  const room = c.env.PANEL_ROOM.get(c.env.PANEL_ROOM.idFromName(envelope.roomId));
  return room.fetch(new Request('https://panel-room.internal/relay', c.req.raw));
}

const routes = new Hono<{ Bindings: Env }>({});
routes.post('/panel-connections', dualAuth, issueConnectionTicket);
routes.get('/panel-relay', upgradeRelay);

export const panelRelayRouter = routes;
