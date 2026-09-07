// Purpose: Integration tests for PanelRoom DO phase 0 spike.
// Exports: none
// Dependencies: cloudflare:test, vitest

import { env } from 'cloudflare:test';
import { describe, it, expect, vi } from 'vitest';
import { runInDurableObject } from 'cloudflare:test';

export type ServerMessage = {
  kind: string;
  epoch?: string;
  sequence?: number;
  code?: string;
  task?: Record<string, unknown>;
  ops?: { op: string; path: string; value?: unknown }[];
  persistedAt?: number;
};

async function connectToRoom(stub: DurableObjectStub) {
  const req = new Request('http://localhost/', {
    headers: { 'Upgrade': 'websocket', 'Sec-WebSocket-Protocol': 'stub-ticket-123' }
  });
  const res = await stub.fetch(req);
  const ws = res.webSocket;
  if (!ws) throw new Error('No websocket');
  ws.accept();
  
  const messages: ServerMessage[] = [];
  ws.addEventListener('message', (ev) => {
    messages.push(JSON.parse(ev.data as string));
  });
  return { ws, messages };
}

describe('PanelRoom', () => {
  it('1. acknowledged update is readable by new subscriber (eviction unproven)', async () => {
    const id = env.PANEL_ROOM!.idFromName('test-1');
    const stub = env.PANEL_ROOM!.get(id);
    const { ws, messages } = await connectToRoom(stub);
    
    // claim lease
    ws.send(JSON.stringify({ kind: 'lease.claim', epoch: 'e1' }));
    await new Promise(r => setTimeout(r, 50));
    
    // send update
    ws.send(JSON.stringify({
      kind: 'state.update',
      epoch: 'e1',
      baseSequence: 0,
      ops: [{ op: 'add', path: '/task/hello', value: 'world' }]
    }));
    await new Promise(r => setTimeout(r, 50));
    
    expect(messages.some(m => m.kind === 'state.ack' && m.sequence === 1)).toBe(true);
    ws.close();
    
    // new subscriber connects
    const { ws: ws2, messages: msg2 } = await connectToRoom(stub);
    await new Promise(r => setTimeout(r, 50));
    
    const snap = msg2.find(m => m.kind === 'state.snapshot');
    expect(snap).toBeDefined();
    expect(snap!.sequence).toBe(1);
    expect(snap!.task).toEqual({ hello: 'world' });
    ws2.close();
  });

  it('1.5. acknowledged update is persisted immediately (not a session log)', async () => {
    const id = env.PANEL_ROOM!.idFromName('test-1-5');
    const stub = env.PANEL_ROOM!.get(id);
    const { ws, messages } = await connectToRoom(stub);
    
    // claim lease
    ws.send(JSON.stringify({ kind: 'lease.claim', epoch: 'e1' }));
    await new Promise(r => setTimeout(r, 50));
    
    // send update
    ws.send(JSON.stringify({
      kind: 'state.update',
      epoch: 'e1',
      baseSequence: 0,
      ops: [{ op: 'add', path: '/task/isolated', value: 'yes' }]
    }));
    await new Promise(r => setTimeout(r, 50));
    
    expect(messages.some(m => m.kind === 'state.ack' && m.sequence === 1)).toBe(true);
    
    // Read directly from SQL, simulating no observer logic
    await runInDurableObject(stub as unknown as DurableObjectStub<import('./room').PanelRoom>, (instance: import('./room').PanelRoom) => {
      const rows = [...instance['ctx'].storage.sql.exec('SELECT * FROM snapshots WHERE id = ?', 'default')];
      expect(rows.length).toBe(1);
      const row = rows[0];
      expect(row.sequence).toBe(1);
      const task = JSON.parse(row.task as string);
      expect(task.isolated).toBe('yes');
      // Verify persisted_at is a real timestamp (distinct from liveness sequence)
      expect(typeof row.persisted_at).toBe('number');
      expect(row.persisted_at as number).toBeGreaterThan(1700000000000); // realistic timestamp
    });
    
    ws.close();
  });

  it('2. snapshot has no gap, patches follow without duplicate array append', async () => {
    const id = env.PANEL_ROOM!.idFromName('test-2');
    const stub = env.PANEL_ROOM!.get(id);
    const { ws: producer, messages: prodMsg } = await connectToRoom(stub);
    
    producer.send(JSON.stringify({ kind: 'lease.claim', epoch: 'e1' }));
    await new Promise(r => setTimeout(r, 50));
    
    // Send 1st update
    producer.send(JSON.stringify({
      kind: 'state.update', epoch: 'e1', baseSequence: 0,
      ops: [{ op: 'add', path: '/task/arr', value: ['a'] }]
    }));
    await new Promise(r => setTimeout(r, 50));
    
    // Connect subscriber at the exact same time as 2nd update
    const req = new Request('http://localhost/', {
      headers: { 'Upgrade': 'websocket', 'Sec-WebSocket-Protocol': 'stub-ticket-123' }
    });
    const res = await stub.fetch(req);
    const subscriber = res.webSocket!;
    subscriber.accept();
    const subMsg: ServerMessage[] = [];
    subscriber.addEventListener('message', ev => subMsg.push(JSON.parse(ev.data as string)));
    
    producer.send(JSON.stringify({
      kind: 'state.update', epoch: 'e1', baseSequence: 1,
      ops: [{ op: 'add', path: '/task/arr/1', value: 'b' }]
    }));
    
    await new Promise(r => setTimeout(r, 50));
    
    // Subscriber should have snapshot first, then any subsequent patches
    expect(subMsg.length).toBeGreaterThan(0);
    const snap = subMsg[0];
    expect(snap.kind).toBe('state.snapshot');
    expect(snap.persistedAt).toBeGreaterThan(1700000000000);
    
    // The snapshot could be seq 1 or seq 2 depending on race, but patches must follow strictly
    let currentSeq = snap.sequence!;
    let arr = (snap.task?.arr as unknown[]) || [];
    
    for (let i = 1; i < subMsg.length; i++) {
       const m = subMsg[i];
       expect(m.kind).toBe('state.patch');
       expect(m.sequence).toBe(currentSeq + 1);
       currentSeq = m.sequence!;
       if (m.ops![0].path.startsWith('/task/arr/')) {
           arr.push(m.ops![0].value);
       }
    }
    
    // Final state should be a, b
    expect(arr).toEqual(['a', 'b']);
    
    producer.close();
    subscriber.close();
  });

  it('3. fenced superseded epoch cannot write', async () => {
    const id = env.PANEL_ROOM!.idFromName('test-3');
    const stub = env.PANEL_ROOM!.get(id);
    const { ws: w1, messages: m1 } = await connectToRoom(stub);
    const { ws: w2, messages: m2 } = await connectToRoom(stub);
    
    // w1 claims e1
    w1.send(JSON.stringify({ kind: 'lease.claim', epoch: 'e1' }));
    await new Promise(r => setTimeout(r, 50));
    
    // w2 claims e2 (supersedes)
    w2.send(JSON.stringify({ kind: 'lease.claim', epoch: 'e2' }));
    await new Promise(r => setTimeout(r, 50));
    
    // w1 tries to write with e1
    w1.send(JSON.stringify({
      kind: 'state.update', epoch: 'e1', baseSequence: 0,
      ops: [{ op: 'add', path: '/task/x', value: 1 }]
    }));
    await new Promise(r => setTimeout(r, 50));
    
    const err = m1.find(m => m.kind === 'error');
    expect(err).toBeDefined();
    expect(err!.code).toBe('lease_conflict');
    
    w1.close();
    w2.close();
  });

  it('4. update with old baseSequence is rejected and drives resync', async () => {
    const id = env.PANEL_ROOM!.idFromName('test-4');
    const stub = env.PANEL_ROOM!.get(id);
    const { ws, messages } = await connectToRoom(stub);
    
    ws.send(JSON.stringify({ kind: 'lease.claim', epoch: 'e1' }));
    await new Promise(r => setTimeout(r, 50));
    
    ws.send(JSON.stringify({
      kind: 'state.update', epoch: 'e1', baseSequence: 0,
      ops: [{ op: 'add', path: '/task/x', value: 1 }]
    }));
    await new Promise(r => setTimeout(r, 50));
    expect(messages.some(m => m.kind === 'state.ack' && m.sequence === 1)).toBe(true);
    
    // Send with old baseSequence 0 instead of 1
    ws.send(JSON.stringify({
      kind: 'state.update', epoch: 'e1', baseSequence: 0,
      ops: [{ op: 'add', path: '/task/y', value: 2 }]
    }));
    await new Promise(r => setTimeout(r, 50));
    
    const err = messages.find(m => m.kind === 'error' && m.code === 'resync_required');
    expect(err).toBeDefined();
    
    ws.close();
  });

  it('5. invalid op anywhere in a patch rejects whole command, nothing partial commits', async () => {
    const id = env.PANEL_ROOM!.idFromName('test-5');
    const stub = env.PANEL_ROOM!.get(id);
    const { ws, messages } = await connectToRoom(stub);
    
    ws.send(JSON.stringify({ kind: 'lease.claim', epoch: 'e1' }));
    await new Promise(r => setTimeout(r, 50));
    
    ws.send(JSON.stringify({
      kind: 'state.update', epoch: 'e1', baseSequence: 0,
      ops: [
        { op: 'add', path: '/task/valid', value: 'ok' },
        { op: 'add', path: '/form/invalid', value: 'bad' } // Confined to /task
      ]
    }));
    await new Promise(r => setTimeout(r, 50));
    
    const err = messages.find(m => m.kind === 'error' && m.code === 'invalid_state');
    expect(err).toBeDefined();
    
    // Verify snapshot did not partially commit
    const { ws: ws2, messages: msg2 } = await connectToRoom(stub);
    await new Promise(r => setTimeout(r, 50));
    
    const snap = msg2.find(m => m.kind === 'state.snapshot');
    expect(snap).toBeDefined();
    expect(snap!.task?.valid).toBeUndefined(); // 'valid' should not exist
    
    ws.close();
    ws2.close();
  });
});
