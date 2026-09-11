// Authorized hibernating WebSocket relay and internal lifecycle gateway.
// Exports PanelRoom; per-panel serialization lives in PanelEngine.
// Dependencies: Cloudflare Durable Objects, ticket store, and lifecycle engine.

import { DurableObject } from 'cloudflare:workers';
import type { Env } from '../../types';
import { isRecord } from '../definition/helpers';
import { faultResponse, PanelFault } from '../lifecycle/types';
import { consumeTicket, issueTicket, type ConnectionAttachment } from './ticket-store';
import { PanelEngine } from './runtime/engine';
import { WallSignals } from './wall/signals';

export class PanelRoom extends DurableObject<Env> {
  private engine: PanelEngine;
  private wall: WallSignals;
  private queues = new WeakMap<WebSocket, Promise<void>>();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS connection_tickets (
      ticket_id TEXT PRIMARY KEY, secret TEXT NOT NULL, room_id TEXT NOT NULL,
      identity TEXT NOT NULL, role TEXT NOT NULL, panel_id TEXT NOT NULL,
      operations TEXT NOT NULL, expires_at INTEGER NOT NULL, consumed_at INTEGER)`);
    this.wall = new WallSignals(ctx, ws => this.attachment(ws));
    this.engine = new PanelEngine(ctx.storage, env.DB, (id, frame) => this.broadcast(id, frame),
      (id, agent, expiry) => this.wall.changed(id, agent, expiry));
  }

  async fetch(req: Request): Promise<Response> {
    const path = new URL(req.url).pathname;
    if (path === '/__issue-ticket' && req.method === 'POST') return issueTicket(this.ctx, req);
    if (path === '/__repair' && req.method === 'POST') { await this.engine.repair(); return new Response(null, { status: 204 }); }
    if (path === '/__command' && req.method === 'POST') return this.command(req);
    if (path === '/__wall-changed' && req.method === 'POST') return this.wallChanged(req);
    if (req.headers.get('Upgrade')?.toLowerCase() !== 'websocket') return new Response('Expected Upgrade: websocket', { status: 426 });
    const consumed = consumeTicket(this.ctx, req.headers.get('X-Panel-Connection-Ticket'));
    if (!consumed.ok) return new Response('Invalid ticket', { status: consumed.status });
    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server, [consumed.ticket.ticketId]);
    server.serializeAttachment(consumed.ticket);
    return new Response(null, { status: 101, webSocket: client });
  }

  private async wallChanged(req: Request): Promise<Response> {
    const input: unknown = await req.json();
    if (!isRecord(input) || typeof input.panelId !== 'string' || typeof input.agentId !== 'string'
      || typeof input.expiresAt !== 'string') return new Response('Invalid signal', { status: 400 });
    await this.wall.changed(input.panelId, input.agentId, input.expiresAt);
    return new Response(null, { status: 204 });
  }

  private async command(req: Request): Promise<Response> {
    try {
      const input = await req.json<unknown>();
      if (!isRecord(input) || typeof input.panelId !== 'string' || typeof input.identity !== 'string'
        || !['producer', 'subscriber'].includes(String(input.role)) || typeof input.action !== 'string') throw new PanelFault('invalid_command', 400);
      const result = await this.engine.execute(input.panelId, input.identity, input.role as 'producer' | 'subscriber', input.action, input.body, typeof input.key === 'string' ? input.key : '');
      return Response.json(result, { status: isRecord(result) && result.status === 'pending' ? 202 : 200 });
    } catch (error) { return faultResponse(error); }
  }

  private attachment(ws: WebSocket): ConnectionAttachment | null {
    const value: unknown = ws.deserializeAttachment();
    if (!isRecord(value) || typeof value.panelId !== 'string' || typeof value.identity !== 'string'
      || !['producer', 'subscriber'].includes(String(value.role)) || !Array.isArray(value.operations)) return null;
    return value as unknown as ConnectionAttachment;
  }

  private broadcast(panelId: string, frame: unknown): void {
    for (const socket of this.ctx.getWebSockets()) {
      if (this.attachment(socket)?.subscribedPanelId !== panelId) continue;
      try { socket.send(JSON.stringify(frame)); } catch { /* Closed projections recover from a fresh snapshot. */ }
    }
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const next = (this.queues.get(ws) ?? Promise.resolve()).then(() => this.dispatch(ws, message));
    this.queues.set(ws, next);
    await next;
  }

  private async dispatch(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    try {
      if (typeof message !== 'string' || message.length > 65_536) throw new PanelFault('invalid_frame', 422);
      let input: unknown;
      try { input = JSON.parse(message); } catch { throw new PanelFault('invalid_json', 400); }
      if (!isRecord(input) || input.protocolVersion !== 2) throw new PanelFault('unsupported_protocol', 400);
      const ticket = this.attachment(ws);
      if (!ticket || input.panelId !== ticket.panelId) throw new PanelFault('permission_denied', 403);
      if (input.kind === 'wall.subscribe' && ticket.operations.includes('wall.subscribe')) {
        ws.serializeAttachment({ ...ticket, subscribedPanelId: 'wall' });
        ws.send(JSON.stringify({ kind: 'wall.changed' }));
        return;
      }
      if (input.kind === 'subscribe' && ticket.operations.includes('subscribe')) {
        const state = await this.engine.execute(ticket.panelId, ticket.identity, ticket.role, 'state', input);
        ws.serializeAttachment({ ...ticket, subscribedPanelId: ticket.panelId });
        ws.send(JSON.stringify({ ...(state as object), kind: 'state.snapshot' }));
        return;
      }
      if (ticket.subscribedPanelId !== ticket.panelId || ticket.role !== 'producer') throw new PanelFault('permission_denied', 403);
      const lease = ['lease.claim', 'lease.renew', 'lease.release'].includes(String(input.kind));
      const update = input.kind === 'state.update' || input.kind === 'state.unchanged';
      const operation = input.kind === 'lease.renew' ? 'lease.claim' : lease ? String(input.kind) : 'state.update';
      if ((!lease && !update) || !ticket.operations.includes(operation as 'lease.claim' | 'lease.release' | 'state.update')) throw new PanelFault('invalid_command', 422);
      const action = input.kind === 'lease.claim' ? 'claim' : input.kind === 'lease.release' ? 'release' : 'renew';
      const body = lease ? { ...input, action } : input;
      const result = await this.engine.execute(ticket.panelId, ticket.identity, ticket.role, lease ? 'lease' : 'update', body);
      ws.send(JSON.stringify(result));
    } catch (error) {
      const fault = error instanceof PanelFault ? error : new PanelFault('service_unavailable', 503);
      try { ws.send(JSON.stringify({ kind: 'error', code: fault.code, retryable: fault.status === 503 })); } catch { /* Socket closed. */ }
    }
  }

  webSocketClose(socket: WebSocket): void { try { socket.close(1000); } catch { /* Already closed. */ } }
  webSocketError(socket: WebSocket): void { socket.close(1011, 'Relay connection failed'); }

  async alarm(): Promise<void> { await this.wall.expire(); await this.engine.repair(); }
}
