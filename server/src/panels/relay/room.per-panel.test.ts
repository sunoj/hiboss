// Multi-connection regression tests for per-panel serialization and isolation.
// Covers racing commands, independent leases, and subscriber write rejection.
// Dependencies: Vitest and authenticated relay test harness.

import { beforeAll, describe, expect, it } from 'vitest';
import { claim, connect, publish, seed, state } from './runtime/test-support';

beforeAll(seed);
describe('panel isolation', () => {
  it('serializes racing updates from separate sockets at the same base sequence', async () => {
    const id = await publish(); const first = await connect(id); const epoch = await claim(first);
    const second = await connect(id); await second.next('state.snapshot');
    for (const [index, connection] of [first, second].entries()) {
      connection.send({ kind: 'state.update', epoch, updateId: `race-${index}`, baseSequence: 0, ops: [{ op: 'replace', path: '/task/done', value: index + 1 }] });
    }
    await first.next('state.patch'); await second.next('state.patch');
    await new Promise(resolve => setTimeout(resolve, 30));
    const frames = [...first.frames, ...second.frames];
    expect(frames.filter(f => f.kind === 'state.ack')).toHaveLength(1);
    expect(frames.filter(f => f.kind === 'error' && f.code === 'resync_required')).toHaveLength(1);
    expect((await state(id)).sequence).toBe(1);
    first.socket.close(); second.socket.close();
  });
  it('keeps panels independent during updates and takeover', async () => {
    const a = await publish(); const b = await publish();
    const first = await connect(a); const second = await connect(b);
    const epochA = await claim(first); const epochB = await claim(second);
    await claim(first, epochA);
    second.send({ kind: 'state.update', epoch: epochB, updateId: 'b', baseSequence: 0, ops: [{ op: 'replace', path: '/task/done', value: 7 }] });
    await second.next('state.ack');
    expect((await state(a)).sequence).toBe(0);
    expect((await state(b)).task).toEqual({ done: 7, items: [] });
    first.socket.close(); second.socket.close();
  });
  it('rejects subscriber writes and ticket scope changes', async () => {
    const a = await publish(); const b = await publish(); const subscriber = await connect(a, true);
    await subscriber.next('state.snapshot');
    subscriber.send({ kind: 'lease.claim', requestId: 'boss-write' });
    expect(await subscriber.next('error')).toMatchObject({ code: 'permission_denied' });
    const start = subscriber.frames.length;
    subscriber.send({ kind: 'subscribe', panelId: b });
    expect(await subscriber.next('error', start)).toMatchObject({ code: 'permission_denied' });
    subscriber.socket.close();
  });
});
