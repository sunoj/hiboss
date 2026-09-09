// Exercises crash recovery against real D1 and Durable Object storage.
// Covers lost commit replies, durable pending fences, expiry, and definition replacement.
// Dependencies: Cloudflare test hooks, PanelEngine DI, and authenticated relay harness.

import { env, SELF, runInDurableObject } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId } from '../../test-helpers';
import { repairPanelRooms } from './repair';
import { PanelEngine } from '../relay/runtime/engine';
import { bossId, claim, connect, publish, seed, state, url } from '../relay/runtime/test-support';
import type { PanelRoom } from '../relay/room';

beforeAll(seed);
const stub = () => env.PANEL_ROOM!.get(env.PANEL_ROOM!.idFromName(bossId)) as DurableObjectStub<PanelRoom>;
const command = { protocolVersion: 2, action: 'complete', expectedMetadataVersion: 1, expectedDefinitionRevision: 1, expectedEpoch: null, expectedState: null, openRequests: 'reject', finalTask: { done: 20, items: ['saved'] } };

describe('durable lifecycle recovery', () => {
  it.each(['before', 'after'] as const)('recovers a database failure %s commit across engine reconstruction', async timing => {
    const id = await publish();
    await runInDurableObject(stub(), async (_instance, context) => {
      const db = new Proxy(env.DB, { get(target, key) {
        if (key === 'batch') return async (statements: D1PreparedStatement[]) => {
          if (timing === 'after') await target.batch(statements);
          throw new Error('Injected lost database response');
        };
        const value: unknown = Reflect.get(target, key);
        return typeof value === 'function' ? value.bind(target) : value;
      } });
      const engine = new PanelEngine(context.storage, db, () => {});
      const pending = await engine.execute(id, getTestAgentId(), 'producer', 'lifecycle', command, 'finish');
      expect(pending).toMatchObject({ status: 'pending' });
      expect(await context.storage.get(`pending:${id}`)).toBeDefined();
      const recovered = new PanelEngine(context.storage, env.DB, () => {});
      await recovered.repair();
      expect(await context.storage.get(`pending:${id}`)).toBeUndefined();
      const receipt = await recovered.execute(id, getTestAgentId(), 'producer', 'lifecycle', command, 'finish');
      expect(receipt).toMatchObject({ metadataVersion: 2, lifecycle: { taskState: 'completed' } });
    });
    expect((await state(id)).task).toEqual({ done: 20, items: ['saved'] });
    const count = await env.DB.prepare('SELECT COUNT(*) AS count FROM panel_operations WHERE panel_id = ?').bind(id).first<{ count: number }>();
    expect(count?.count).toBe(1);
  });

  it('rejects writes after lease expiry and issues a fresh server epoch', async () => {
    const id = await publish(); const producer = await connect(id); const epoch = await claim(producer);
    producer.send({ kind: 'state.unchanged', epoch, updateId: 'before-expiry', baseSequence: 0 });
    await producer.next('state.ack');
    const prior = await state(id);
    await runInDurableObject(stub(), async (_instance, context) => {
      const lease = await context.storage.get<Record<string, unknown>>(`lease:${id}`);
      await context.storage.put(`lease:${id}`, { ...lease, expiresAt: Date.now() - 1 });
    });
    producer.send({ kind: 'state.unchanged', epoch, updateId: 'expired', baseSequence: 0 });
    expect(await producer.next('error')).toMatchObject({ code: 'fenced_epoch' });
    expect(await claim(producer)).not.toBe(epoch);
    expect(await state(id)).toMatchObject({ lastObservedAt: prior.lastObservedAt, expiresAt: prior.expiresAt, observationVersion: prior.observationVersion });
    producer.socket.close();
  });

  it('keeps an expired running panel readable without changing stored state', async () => {
    const id = await publish({ mode: 'monitor', expectedUpdateIntervalSeconds: 5, ttlSeconds: 60 });
    const producer = await connect(id); const epoch = await claim(producer);
    producer.send({ kind: 'state.unchanged', epoch, updateId: 'expiry-observation', baseSequence: 0 });
    await producer.next('state.ack');
    const before = await runInDurableObject(stub(), async (_instance, context) => context.storage.get<Record<string, unknown>>(`snapshot:${id}`));
    await runInDurableObject(stub(), async (_instance, context) => {
      const snapshot = await context.storage.get<Record<string, unknown>>(`snapshot:${id}`);
      await context.storage.put(`snapshot:${id}`, { ...snapshot, lastObservedAt: new Date(Date.now() - 61_000).toISOString() });
    });
    const checkpoint = await state(id);
    expect(Date.parse(checkpoint.expiresAt)).toBeLessThan(Date.now());
    const metadata = await (await SELF.fetch(`${url}/${id}`, { headers: authHeaders() })).json<{ lifecycle: { taskState: string } }>();
    expect(metadata.lifecycle.taskState).toBe('running');
    const after = await runInDurableObject(stub(), async (_instance, context) => context.storage.get(`snapshot:${id}`));
    expect(after).toEqual({ ...before, lastObservedAt: expect.any(String) });
    producer.socket.close();
  });

  it('replaces a definition atomically and rejects patches for its prior revision', async () => {
    const id = await publish(); const producer = await connect(id); const epoch = await claim(producer);
    const detail = await (await SELF.fetch(`${url}/${id}`, { headers: authHeaders() })).json<{ definition: Record<string, unknown> }>();
    const { catalogId, catalogVersion, spec, stateSchema } = detail.definition;
    const summary = { stage: 'Revised', headline: { path: '/task/done', label: 'Done' } };
    const response = await SELF.fetch(`${url}/${id}/definition`, { method: 'PUT', headers: { ...authHeaders(), 'Idempotency-Key': 'replace' }, body: JSON.stringify({
      protocolVersion: 2, expectedMetadataVersion: 1, expectedDefinitionRevision: 1, expectedEpoch: epoch, expectedState: { epoch, sequence: 0 },
      catalogId, catalogVersion, spec, stateSchema, summary, initialState: { task: { done: 5, items: ['baseline'] } },
    }) });
    expect(response.status).toBe(200);
    const replaced = await (await SELF.fetch(`${url}/${id}`, { headers: authHeaders() })).json<{ summary: unknown }>();
    expect(replaced.summary).toEqual(summary);
    expect(await state(id)).toMatchObject({ definitionRevision: 2, sequence: 0, epoch: null, observationVersion: 0, task: { done: 5, items: ['baseline'] } });
    producer.send({ kind: 'lease.claim', requestId: 'old-revision' });
    expect(await producer.next('error')).toMatchObject({ code: 'revision_conflict' });
    producer.socket.close();
  });
  it('rejects invalid summary bindings and clears omitted summaries on replacement', async () => {
    const id = await publish();
    const detail = await (await SELF.fetch(`${url}/${id}`, { headers: authHeaders() })).json<{ definition: Record<string, unknown> }>();
    const { catalogId, catalogVersion, spec, stateSchema, initialState } = detail.definition;
    const body = { protocolVersion: 2, expectedMetadataVersion: 1, expectedDefinitionRevision: 1,
      expectedEpoch: null, expectedState: { epoch: null, sequence: 0 }, catalogId, catalogVersion, spec, stateSchema, initialState };
    const replace = (value: unknown) => SELF.fetch(`${url}/${id}/definition`, { method: 'PUT', headers: { ...authHeaders(), 'Idempotency-Key': 'summary' }, body: JSON.stringify(value) });
    const invalid = await replace({ ...body, summary: { stage: 'Invalid', headline: { path: '/task/missing', label: 'Missing' } } });
    expect(invalid.status).toBe(422);
    await env.DB.prepare('UPDATE panels SET summary_json = ? WHERE panel_id = ?').bind(JSON.stringify({ stage: 'Old' }), id).run();
    expect((await replace(body)).status).toBe(200);
    const updated = await (await SELF.fetch(`${url}/${id}`, { headers: authHeaders() })).json<{ summary: unknown; metadataVersion: number }>();
    expect(updated.summary).toEqual({});
    expect(updated.metadataVersion).toBe(2);
  });
  it('recovers an operation after its alarm is lost', async () => {
    const id = await publish();
    await runInDurableObject(stub(), async (_instance, context) => {
      const db = new Proxy(env.DB, { get(target, key) {
        if (key === 'batch') return async () => { throw new Error('Database unavailable'); };
        const value: unknown = Reflect.get(target, key);
        return typeof value === 'function' ? value.bind(target) : value;
      } });
      const engine = new PanelEngine(context.storage, db, () => {});
      expect(await engine.execute(id, getTestAgentId(), 'producer', 'lifecycle', command, 'lost-alarm')).toMatchObject({ status: 'pending' });
      await context.storage.deleteAlarm();
    });
    await repairPanelRooms(env);
    expect((await state(id)).task).toEqual({ done: 20, items: ['saved'] });
    const row = await env.DB.prepare('SELECT metadata_version FROM panels WHERE panel_id = ?').bind(id).first<{ metadata_version: number }>();
    expect(row?.metadata_version).toBe(2);
  });

});
