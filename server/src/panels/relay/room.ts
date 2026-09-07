// Purpose: Minimal SQLite-backed PanelRoom DO for phase 0 relay spike.
// Exports: PanelRoom
// Dependencies: cloudflare:workers, types

import { DurableObject } from 'cloudflare:workers';
import type { Env } from '../../types';

interface UpdateCommand {
  kind: 'state.update';
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
  }

  async fetch(req: Request) {
    if (req.headers.get('Upgrade') !== 'websocket') {
      return new Response('Expected Upgrade: websocket', { status: 426 });
    }
    
    // Stub ticket check
    const ticket = req.headers.get('Sec-WebSocket-Protocol');
    if (ticket !== 'stub-ticket-123') {
      return new Response('Invalid ticket', { status: 401 });
    }

    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server, [ticket]);
    
    // Send initial snapshot before any patches
    const snap = this.getSnapshot();
    if (snap) {
      server.send(JSON.stringify({ kind: 'state.snapshot', epoch: snap.epoch, sequence: snap.sequence, task: snap.task, persistedAt: snap.persistedAt }));
    } else {
      server.send(JSON.stringify({ kind: 'state.snapshot', sequence: 0, task: {} }));
    }

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

  webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    try {
      const msg = JSON.parse(message as string);
      
      if (msg.kind === 'lease.claim') {
        this.setLease(msg.epoch);
        ws.send(JSON.stringify({ kind: 'lease.ack', epoch: msg.epoch }));
        return;
      }

      if (msg.kind === 'state.update') {
        const cmd = msg as UpdateCommand;
        const currentEpoch = this.getLease();
        
        if (currentEpoch && currentEpoch !== cmd.epoch) {
           ws.send(JSON.stringify({ kind: 'error', code: 'lease_conflict' }));
           return;
        }

        const snap = this.getSnapshot() || { epoch: cmd.epoch, sequence: 0, task: {} };
        if (snap.sequence !== cmd.baseSequence) {
           ws.send(JSON.stringify({ kind: 'error', code: 'resync_required' }));
           return;
        }

        let taskCopy = JSON.parse(JSON.stringify(snap.task));
        
        try {
          for (const op of cmd.ops) {
             if (op.path === '/task') {
               if (op.op === 'replace' || op.op === 'add') taskCopy = op.value;
               else if (op.op === 'remove') taskCopy = {};
               continue;
             }
             if (!op.path.startsWith('/task/')) throw new Error('Confined to /task');
             
             const relPath = op.path.slice('/task/'.length);
             const parts = relPath.split('/');
             let target = taskCopy;
             for (let i = 0; i < parts.length - 1; i++) {
                if (!target[parts[i]]) target[parts[i]] = {};
                target = target[parts[i]];
             }
             const last = parts[parts.length - 1];
             
             if (op.op === 'replace' || op.op === 'add') {
                target[last] = op.value;
             } else if (op.op === 'remove') {
                delete target[last];
             } else {
                throw new Error('Invalid operation');
             }
          }
        } catch (err) {
           ws.send(JSON.stringify({ kind: 'error', code: 'invalid_state', message: String(err) }));
           return; // Reject whole command
        }
        
        const newSeq = snap.sequence + 1;
        this.ctx.storage.sql.exec('INSERT OR REPLACE INTO snapshots (id, epoch, sequence, task, persisted_at) VALUES (?, ?, ?, ?, ?)', 
          'default', cmd.epoch, newSeq, JSON.stringify(taskCopy), Date.now());
        
        const ack = { kind: 'state.ack', sequence: newSeq };
        const patch = { kind: 'state.patch', sequence: newSeq, ops: cmd.ops };
        
        ws.send(JSON.stringify(ack));
        for (const sock of this.ctx.getWebSockets()) {
           sock.send(JSON.stringify(patch));
        }
      }
    } catch (err) {
      ws.send(JSON.stringify({ kind: 'error', code: 'invalid_json' }));
    }
  }

  webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean) {}
  webSocketError(ws: WebSocket, error: unknown) {}
}
