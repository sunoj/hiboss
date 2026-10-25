// Re-authorizes boss subscriber sockets against D1 before the room sends them anything.
// Exports SubscriberGate: a revoked token or client, an archive, a demotion or a lost grant closes the socket (4401).
// Dependencies: D1 boss credentials and the panel access policy in ../access.ts.

import type { ConnectionAttachment } from './ticket-store';

const MAX_BINDS = 90;

interface LiveToken { id: string; boss_id: string }

// Mirrors lifecycle authorize() for subscribers: the target boss, or any admin, with access to the agent.
const PANEL_ACCESS = `EXISTS (SELECT 1 FROM panels p WHERE p.panel_id = ?
  AND (p.target_boss_id = b.id OR b.role = 'admin')
  AND (b.role = 'admin' OR EXISTS (SELECT 1 FROM boss_agent_access a WHERE a.boss_id = b.id AND a.agent_id = p.agent_id)))`;

export class SubscriberGate {
  constructor(private db: D1Database, private attachment: (ws: WebSocket) => ConnectionAttachment | null) {}

  /**
   * Returns the sockets that may receive a frame of `panelId` (null for the wall). Producer sockets
   * pass; a subscriber passes only while its token is live and it can still read the panel. A
   * failed check sends nothing and closes nothing: the next frame checks again.
   */
  async admit(sockets: readonly WebSocket[], panelId: string | null): Promise<WebSocket[]> {
    const subscribers = sockets.filter(socket => this.attachment(socket)?.role === 'subscriber');
    if (subscribers.length === 0) return [...sockets];
    let live: Set<string>;
    try { live = await this.liveTokens(subscribers, panelId); } catch { return sockets.filter(s => !subscribers.includes(s)); }
    return sockets.filter(socket => {
      const ticket = this.attachment(socket);
      if (ticket?.role !== 'subscriber') return true;
      if (ticket.tokenId && live.has(`${ticket.tokenId}:${ticket.identity}`)) return true;
      // Stop broadcasts immediately, including while the close handshake is pending.
      socket.serializeAttachment(null);
      try { socket.close(4401, 'access revoked'); } catch { /* Already closed. */ }
      return false;
    });
  }

  private async liveTokens(sockets: readonly WebSocket[], panelId: string | null): Promise<Set<string>> {
    const ids = [...new Set(sockets.map(socket => this.attachment(socket)?.tokenId).filter((id): id is string => !!id))];
    const live = new Set<string>();
    for (let start = 0; start < ids.length; start += MAX_BINDS) {
      const chunk = ids.slice(start, start + MAX_BINDS);
      const rows = await this.db.prepare(`SELECT t.id, t.boss_id FROM boss_tokens t JOIN bosses b ON b.id = t.boss_id
        LEFT JOIN boss_clients c ON c.id = t.client_id
        WHERE t.id IN (${chunk.map(() => '?').join(', ')}) AND t.revoked_at IS NULL
        AND (t.client_id IS NULL OR c.revoked_at IS NULL) AND b.archived_at IS NULL
        ${panelId === null ? '' : `AND ${PANEL_ACCESS}`}`)
        .bind(...chunk, ...(panelId === null ? [] : [panelId])).all<LiveToken>();
      for (const row of rows.results ?? []) live.add(`${row.id}:${row.boss_id}`);
    }
    return live;
  }
}
