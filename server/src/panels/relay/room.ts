// Purpose: Authorized SQLite-backed PanelRoom DO for scoped live panel relay.
// Exports: PanelRoom
// Dependencies: Cloudflare Durable Objects, D1 panel visibility, and ticket types.

import { DurableObject } from 'cloudflare:workers';
import type { Env } from '../../types';
import {
  type PanelOperation,
} from './ticket';
import { consumeTicket, issueTicket, type ConnectionAttachment } from './ticket-store';

interface UpdateCommand {
  kind: 'state.update';
  panelId: string;
  epoch: string;
  baseSequence: number;
  ops: { op: 'replace' | 'add' | 'remove'; path: string; value?: unknown }[];
}

export class PanelRoom extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS snapshots (
        id TEXT PRIMARY KEY,
        epoch TEXT,
        sequence INTEGER,
        task TEXT,
        persisted_at INTEGER
      )
    `);
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS leases (
        id TEXT PRIMARY KEY,
        epoch TEXT
      )
    `);
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS connection_tickets (
        ticket_id TEXT PRIMARY KEY,
        secret TEXT NOT NULL,
        room_id TEXT NOT NULL,
        identity TEXT NOT NULL,
        role TEXT NOT NULL,
        panel_id TEXT NOT NULL,
        operations TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        consumed_at INTEGER
      )
    `);
  }

  async fetch(req: Request): Promise<Response> {
    if (new URL(req.url).pathname === '/__issue-ticket' && req.method === 'POST') return issueTicket(this.ctx, req);
    if (req.headers.get('Upgrade') !== 'websocket') {
      return new Response('Expected Upgrade: websocket', { status: 426 });
    }

    const consumed = consumeTicket(this.ctx, req.headers.get('X-Panel-Connection-Ticket'));
    if (!consumed.ok) return new Response(consumed.status === 410 ? 'Expired ticket' : 'Invalid ticket', { status: consumed.status });
    const ticket = consumed.ticket;

    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server, [ticket.ticketId]);
    server.serializeAttachment(ticket);

    return new Response(null, { status: 101, webSocket: client });
  }

  getSnapshot() {
    const rows = [...this.ctx.storage.sql.exec('SELECT * FROM snapshots WHERE id = ?', 'default')];
    const row = rows[0];
    if (row) {
      return { 
        epoch: row.epoch as string, 
        sequence: row.sequence as number, 
        task: JSON.parse(row.task as string),
        persistedAt: row.persisted_at as number
      };
    }
    return null;
  }

  setLease(epoch: string) {
    this.ctx.storage.sql.exec('INSERT OR REPLACE INTO leases (id, epoch) VALUES (?, ?)', 'default', epoch);
  }

  getLease() {
    const rows = [...this.ctx.storage.sql.exec('SELECT * FROM leases WHERE id = ?', 'default')];
    const row = rows[0];
    return row ? (row.epoch as string) : null;
  }

  private attachment(ws: WebSocket): ConnectionAttachment | null {
    const value = ws.deserializeAttachment() as unknown;
    if (!value || typeof value !== 'object') return null;
    const attachment = value as Partial<ConnectionAttachment>;
    return typeof attachment.ticketId === 'string' && typeof attachment.roomId === 'string'
      && typeof attachment.identity === 'string' && (attachment.role === 'producer' || attachment.role === 'subscriber')
      && typeof attachment.panelId === 'string' && Array.isArray(attachment.operations)
      ? attachment as ConnectionAttachment
      : null;
  }

  private hasOperation(ticket: ConnectionAttachment, operation: PanelOperation): boolean {
    return ticket.operations.includes(operation);
  }

  private sendError(ws: WebSocket, code: string): void {
    ws.send(JSON.stringify({ kind: 'error', code }));
  }

  private async canAccessPanel(ticket: ConnectionAttachment, panelId: string): Promise<boolean> {
    if (ticket.panelId !== panelId) return false;
    if (ticket.role === 'producer') {
      const row = await this.env.DB.prepare('SELECT 1 AS allowed FROM panels WHERE panel_id = ? AND agent_id = ? AND target_boss_id = ? LIMIT 1')
        .bind(panelId, ticket.identity, ticket.roomId).first<{ allowed: number }>();
      return row !== null;
    }
    const row = await this.env.DB.prepare(
      'SELECT 1 AS allowed FROM panels p JOIN boss_agent_access ba ON ba.agent_id = p.agent_id AND ba.boss_id = ? WHERE p.panel_id = ? AND p.target_boss_id = ? LIMIT 1',
    ).bind(ticket.identity, panelId, ticket.roomId).first<{ allowed: number }>();
    return row !== null;
  }

  private sendSnapshot(ws: WebSocket): void {
    const snap = this.getSnapshot();
    ws.send(JSON.stringify(snap
      ? { kind: 'state.snapshot', epoch: snap.epoch, sequence: snap.sequence, task: snap.task, persistedAt: snap.persistedAt }
      : { kind: 'state.snapshot', sequence: 0, task: {} }));
  }

  private async handleSubscribe(ws: WebSocket, ticket: ConnectionAttachment, panelId: unknown): Promise<void> {
    if (!this.hasOperation(ticket, 'subscribe') || typeof panelId !== 'string' || !await this.canAccessPanel(ticket, panelId)) {
      this.sendError(ws, 'permission_denied');
      return;
    }
    ws.serializeAttachment({ ...ticket, subscribedPanelId: panelId });
    this.sendSnapshot(ws);
  }

  private async handleLeaseClaim(ws: WebSocket, ticket: ConnectionAttachment, msg: Record<string, unknown>): Promise<void> {
    const panelId = msg.panelId;
    if (ticket.role !== 'producer' || !this.hasOperation(ticket, 'lease.claim') || typeof panelId !== 'string'
      || ticket.subscribedPanelId !== panelId || !await this.canAccessPanel(ticket, panelId)) {
      this.sendError(ws, 'permission_denied');
      return;
    }
    if (typeof msg.epoch !== 'string' || !msg.epoch) {
      this.sendError(ws, 'invalid_lease');
      return;
    }
    this.setLease(msg.epoch);
    ws.send(JSON.stringify({ kind: 'lease.ack', epoch: msg.epoch }));
  }

  private async handleStateUpdate(ws: WebSocket, ticket: ConnectionAttachment, msg: UpdateCommand): Promise<void> {
    if (ticket.role !== 'producer' || !this.hasOperation(ticket, 'state.update') || ticket.subscribedPanelId !== msg.panelId
      || !await this.canAccessPanel(ticket, msg.panelId)) {
      this.sendError(ws, 'permission_denied');
      return;
    }
    const currentEpoch = this.getLease();
    if (currentEpoch && currentEpoch !== msg.epoch) {
      this.sendError(ws, 'lease_conflict');
      return;
    }
    const snap = this.getSnapshot() || { epoch: msg.epoch, sequence: 0, task: {} };
    if (snap.sequence !== msg.baseSequence) {
      this.sendError(ws, 'resync_required');
      return;
    }
    let taskCopy = JSON.parse(JSON.stringify(snap.task));
    try {
      for (const op of msg.ops) {
        if (op.path === '/task') {
          if (op.op === 'replace' || op.op === 'add') taskCopy = op.value;
          else if (op.op === 'remove') taskCopy = {};
          continue;
        }
        if (!op.path.startsWith('/task/')) throw new Error('Confined to /task');
        const parts = op.path.slice('/task/'.length).split('/');
        let target = taskCopy;
        for (let i = 0; i < parts.length - 1; i++) {
          if (!target[parts[i]]) target[parts[i]] = {};
          target = target[parts[i]];
        }
        const last = parts[parts.length - 1];
        if (op.op === 'replace' || op.op === 'add') target[last] = op.value;
        else if (op.op === 'remove') delete target[last];
        else throw new Error('Invalid operation');
      }
    } catch (error) {
      this.sendError(ws, 'invalid_state');
      return;
    }
    const newSeq = snap.sequence + 1;
    this.ctx.storage.sql.exec('INSERT OR REPLACE INTO snapshots (id, epoch, sequence, task, persisted_at) VALUES (?, ?, ?, ?, ?)',
      'default', msg.epoch, newSeq, JSON.stringify(taskCopy), Date.now());
    ws.send(JSON.stringify({ kind: 'state.ack', sequence: newSeq }));
    this.broadcastPatch(msg.panelId, { kind: 'state.patch', sequence: newSeq, ops: msg.ops });
  }

  private broadcastPatch(panelId: string, patch: object): void {
    for (const sock of this.ctx.getWebSockets()) {
      if (this.attachment(sock)?.subscribedPanelId === panelId) sock.send(JSON.stringify(patch));
    }
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    try {
      const msg = JSON.parse(message as string) as Record<string, unknown>;
      const ticket = this.attachment(ws);
      if (!ticket) return this.sendError(ws, 'invalid_connection');
      if (msg.kind === 'subscribe') return this.handleSubscribe(ws, ticket, msg.panelId);
      if (msg.kind === 'lease.claim') return this.handleLeaseClaim(ws, ticket, msg);
      if (msg.kind === 'state.update') return this.handleStateUpdate(ws, ticket, msg as unknown as UpdateCommand);
    } catch {
      this.sendError(ws, 'invalid_json');
    }
  }

  webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean) {}
  webSocketError(ws: WebSocket, error: unknown) {}
}
