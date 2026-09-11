// Fans out content-free wall invalidations and schedules durable visibility expiry.
// Exports WallSignals; dependencies: DO storage and authenticated socket attachments.

import type { ConnectionAttachment } from '../ticket-store';

interface WallExpiry { agentId: string; expiresAt: number }

export class WallSignals {
  constructor(private ctx: DurableObjectState, private attachment: (ws: WebSocket) => ConnectionAttachment | null) {}

  async changed(panelId: string, agentId: string, expiresAt: string): Promise<void> {
    const expiry = Date.parse(expiresAt);
    if (Number.isFinite(expiry) && expiry > Date.now()) {
      await this.ctx.storage.put(`wall-expiry:${panelId}`, { agentId, expiresAt: expiry });
      await this.schedule(expiry);
    } else {
      await this.ctx.storage.delete(`wall-expiry:${panelId}`);
    }
    this.broadcast(agentId);
  }

  private broadcast(agentId: string): void {
    for (const socket of this.ctx.getWebSockets()) {
      const ticket = this.attachment(socket);
      if (!ticket?.operations.includes('wall.subscribe') || ticket.subscribedPanelId !== 'wall') continue;
      if (ticket.role === 'producer' && ticket.identity !== agentId) continue;
      // No panel identifiers or metadata: REST rechecks current access after invalidation.
      try { socket.send(JSON.stringify({ kind: 'wall.changed' })); } catch { /* Reconnect reconciles. */ }
    }
  }

  async expire(): Promise<void> {
    const entries = await this.ctx.storage.list<WallExpiry>({ prefix: 'wall-expiry:' });
    const agents = new Set<string>();
    let next = Infinity;
    for (const [key, expiry] of entries) {
      if (expiry.expiresAt > Date.now()) { next = Math.min(next, expiry.expiresAt); continue; }
      await this.ctx.storage.delete(key);
      agents.add(expiry.agentId);
    }
    for (const agent of agents) this.broadcast(agent);
    if (Number.isFinite(next)) await this.schedule(next);
  }

  private async schedule(time: number): Promise<void> {
    const alarm = await this.ctx.storage.getAlarm();
    if (alarm === null || time < alarm) await this.ctx.storage.setAlarm(time);
  }
}
