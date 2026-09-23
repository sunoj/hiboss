// Real wall sockets and a controllable internal signal boundary for questionnaire E2E tests.
// Exports socket, discovery, and relay probe helpers using Worker/D1/PanelRoom.

import { env, SELF, runInDurableObject } from 'cloudflare:test';
import { expect } from 'vitest';
import type { PanelRoom } from '../../relay/room';
import { base, BOSS, bossHeaders } from './support';

interface WallConnection { socket: WebSocket; frames: unknown[] }
interface Signal { panelId: string; agentId: string; expiresAt: string }
export interface SignalProbe {
  inputs: Signal[];
  completed: number;
  fail: boolean;
  paused: boolean;
  restore: () => Promise<void>;
}
export async function wall(headers: Record<string, string>): Promise<WallConnection> {
  const issued = await SELF.fetch(`${base}/panel-wall-connections`, {
    method: 'POST', headers, body: JSON.stringify({ targetBossId: BOSS }),
  });
  expect(issued.status).toBe(201);
  const { ticket } = await issued.json<{ ticket: string }>();
  const response = await SELF.fetch(`${base}/panel-relay`, {
    headers: { Upgrade: 'websocket', 'X-Panel-Connection-Ticket': ticket },
  });
  const socket = response.webSocket;
  if (!socket) throw new Error('Missing wall socket');
  socket.accept();
  const frames: unknown[] = [];
  socket.addEventListener('message', event => { frames.push(JSON.parse(String(event.data))); });
  socket.send(JSON.stringify({ protocolVersion: 2, kind: 'wall.subscribe', panelId: 'wall' }));
  await expect.poll(() => frames.length).toBe(1);
  expect(frames).toEqual([{ kind: 'wall.changed' }]);
  return { socket, frames };
}
export async function signalProbe(): Promise<SignalProbe> {
  if (!env.PANEL_ROOM) throw new Error('Missing PanelRoom');
  const room = env.PANEL_ROOM.get(env.PANEL_ROOM.idFromName(BOSS)) as DurableObjectStub<PanelRoom>;
  const probe: SignalProbe = { inputs: [], completed: 0, fail: false, paused: false, restore: async () => {} };
  await runInDurableObject(room, async instance => {
    const original = instance.fetch;
    instance.fetch = async request => {
      if (new URL(request.url).pathname !== '/__wall-changed') return original.call(instance, request);
      probe.inputs.push(await request.clone().json<Signal>());
      // Keep timer I/O inside this Durable Object rather than sharing promises across contexts.
      while (probe.paused) await scheduler.wait(5);
      const response = probe.fail ? new Response(null, { status: 503 }) : await original.call(instance, request);
      probe.completed += 1;
      return response;
    };
    probe.restore = async () => { await runInDurableObject(room, async current => { current.fetch = original; }); };
  });
  return probe;
}
export async function pending(headers: Record<string, string> = bossHeaders): Promise<unknown[]> {
  const response = await SELF.fetch(`${base}/interaction-requests`, { headers });
  expect(response.status).toBe(200);
  return (await response.json<{ requests: unknown[] }>()).requests;
}
export async function expectSignals(connections: WallConnection[], count: number): Promise<void> {
  for (const connection of connections) {
    await expect.poll(() => connection.frames.length).toBe(count);
    expect(connection.frames).toEqual(Array.from({ length: count }, () => ({ kind: 'wall.changed' })));
  }
}
