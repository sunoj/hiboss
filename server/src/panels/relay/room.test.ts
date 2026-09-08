// End-to-end v2 relay tests for observations, persistence, and producer ownership.
// Covers real ticket issuance, WebSockets, and authenticated finalization.
// Dependencies: Cloudflare runtime, Vitest, and relay test harness.

import { beforeAll, describe, expect, it } from 'vitest';
import { claim, connect, control, publish, seed, state } from './runtime/test-support';

beforeAll(seed);
describe('v2 live relay', () => {
  it('handles back-to-back subscribe/claim and restores acknowledged data for a new subscriber', async () => {
    const id = await publish();
    const producer = await connect(id);
    const epoch = await claim(producer);
    producer.send({ kind: 'state.update', epoch, updateId: 'one', baseSequence: 0, ops: [{ op: 'replace', path: '/task/done', value: 9 }] });
    expect(await producer.next('state.ack')).toMatchObject({ sequence: 1, observationVersion: 1, task: { done: 9, items: [] } });
    producer.socket.close();
    const subscriber = await connect(id, true);
    expect(await subscriber.next('state.snapshot')).toMatchObject({ sequence: 1, task: { done: 9, items: [] } });
    subscriber.socket.close();
  });

  it('renews ownership without refreshing data, while a genuine unchanged observation refreshes it', async () => {
    const id = await publish(); const producer = await connect(id); const epoch = await claim(producer);
    const baseline = await state(id);
    expect(baseline.lastObservedAt).toBeNull();
    producer.send({ kind: 'lease.renew', epoch });
    await producer.next('state.observation');
    expect((await state(id)).observationVersion).toBe(0);
    producer.send({ kind: 'state.unchanged', epoch, updateId: 'observed', baseSequence: 0 });
    const ack = await producer.next('state.ack');
    expect(ack).toMatchObject({ sequence: 0, observationVersion: 1 });
    expect(Date.parse(ack.staleAt!) - Date.parse(ack.lastObservedAt!)).toBe(15_000);
    producer.socket.close();
  });

  it('deduplicates array append and rejects invalid patches atomically', async () => {
    const id = await publish(); const producer = await connect(id); const epoch = await claim(producer);
    const update = { kind: 'state.update', epoch, updateId: 'append', baseSequence: 0, ops: [{ op: 'add', path: '/task/items/-', value: 'a' }] };
    producer.send(update); const first = await producer.next('state.ack');
    const start = producer.frames.length; producer.send(update);
    expect(await producer.next('state.ack', start)).toEqual(first);
    producer.send({ ...update, updateId: 'invalid', baseSequence: 1, ops: [{ op: 'replace', path: '/task/done', value: 5 }, { op: 'add', path: '/form/x', value: 'bad' }] });
    expect(await producer.next('error')).toMatchObject({ code: 'invalid_state' });
    expect((await state(id)).task).toEqual({ done: 0, items: ['a'] });
    producer.socket.close();
  });

  it('requires explicit takeover and fences the prior producer', async () => {
    const id = await publish(); const first = await connect(id); const epoch = await claim(first);
    const second = await connect(id);
    second.send({ kind: 'lease.claim', requestId: 'uninvited' });
    expect(await second.next('error')).toMatchObject({ code: 'lease_conflict' });
    const replacement = await claim(second, epoch); expect(replacement).not.toBe(epoch);
    first.send({ kind: 'state.unchanged', epoch, updateId: 'old', baseSequence: 0 });
    expect(await first.next('error')).toMatchObject({ code: 'fenced_epoch' });
    first.socket.close(); second.socket.close();
  });

  it('pauses a live producer, resumes with new ownership, and freezes the completed result', async () => {
    const id = await publish(); const producer = await connect(id); const epoch = await claim(producer);
    expect((await control(id, 'pause', 1, await state(id))).status).toBe(200);
    producer.send({ kind: 'state.unchanged', epoch, updateId: 'paused', baseSequence: 0 });
    expect(await producer.next('error')).toMatchObject({ code: 'panel_paused' });
    expect((await control(id, 'resume', 2, await state(id))).status).toBe(200);
    const newEpoch = await claim(producer); expect(newEpoch).not.toBe(epoch);
    expect((await control(id, 'complete', 3, await state(id))).status).toBe(200);
    const final = await state(id);
    const start = producer.frames.length;
    producer.send({ kind: 'state.update', epoch: newEpoch, updateId: 'late', baseSequence: 0, ops: [{ op: 'replace', path: '/task/done', value: 99 }] });
    expect(await producer.next('error', start)).toMatchObject({ code: 'panel_ended' });
    expect(await state(id)).toMatchObject({ task: final.task, epoch: final.epoch, sequence: final.sequence, observationVersion: final.observationVersion });
    producer.socket.close();
  });
});
