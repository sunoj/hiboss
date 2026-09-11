// Serializes per-panel producer ownership and durable lifecycle recovery.
// Exports PanelEngine used by HTTP control and WebSocket state operations.
// Dependencies: DO storage, D1 lifecycle repository, and safe patch application.

import { bodyHash, isRecord } from '../../definition/helpers';
import { commitControl, parseControl, prepareControl, type PendingControl } from '../../lifecycle/control';
import { authorize, initialCheckpoint, operationReceipt, readRecord, validateTask, type PanelRecord } from '../../lifecycle/repository';
import { DEFAULT_TTL_SECONDS, LEASE_MS, MAX_TTL_SECONDS, MIN_TTL_SECONDS, PanelFault, terminal, type Checkpoint, type Lifecycle } from '../../lifecycle/types';
import { prepareDefinition } from '../../lifecycle/definition';
import { applyTaskPatch } from './patch';

interface Lease { epoch: string; expiresAt: number; requestId: string; hash: string; }
interface UpdateReceipt { id: string; hash: string; expiresAt: number; frame: Checkpoint & { kind: string }; }
export class PanelEngine {
  private queues = new Map<string, Promise<unknown>>();
  constructor(private storage: DurableObjectStorage, private db: D1Database, private broadcast: (panelId: string, frame: unknown) => void,
    private wallChanged: (panelId: string, agentId: string, expiresAt: string) => Promise<void>) {}

  async execute(panelId: string, identity: string, role: 'producer' | 'subscriber', action: string, body: unknown, key = ''): Promise<unknown> {
    const previous = this.queues.get(panelId) ?? Promise.resolve();
    const next = previous.catch(() => {}).then(async () => {
      const row = await readRecord(this.db, panelId);
      await authorize(this.db, row, identity, role);
      if (action === 'operation') return await this.operation(row, body);
      if (action === 'state') return await this.snapshot(row);
      if (action === 'renew') {
        if (role !== 'producer') throw new PanelFault('permission_denied', 403);
        return await this.renew(row, body, key);
      }
      if (role !== 'producer') throw new PanelFault('permission_denied', 403);
      if (action === 'lifecycle' || action === 'definition') return await this.control(row, identity, body, key, action);
      await this.recover(panelId);
      const current = await readRecord(this.db, panelId);
      if (!isRecord(body) || body.protocolVersion !== 2) throw new PanelFault('unsupported_protocol', 400);
      if (action === 'lease') return await this.lease(current, body);
      if (action === 'update') return await this.update(current, body);
      throw new PanelFault('invalid_command', 422);
    });
    this.queues.set(panelId, next);
    try { return await next; } finally { if (this.queues.get(panelId) === next) this.queues.delete(panelId); }
  }

  private async operation(row: PanelRecord, body: unknown): Promise<unknown> {
    if (!isRecord(body) || typeof body.operationId !== 'string') throw new PanelFault('invalid_command', 400);
    const committed = await this.db.prepare('SELECT receipt_json FROM panel_operations WHERE panel_id = ? AND operation_id = ?')
      .bind(row.panel_id, body.operationId).first<{ receipt_json: string }>();
    if (committed) return JSON.parse(committed.receipt_json) as unknown;
    const pending = await this.storage.get<PendingControl>(`pending:${row.panel_id}`);
    if (pending?.operationId === body.operationId) return { status: 'pending', operationId: pending.operationId };
    throw new PanelFault('not_found', 404);
  }

  private async snapshot(row: PanelRecord): Promise<Checkpoint> {
    const lifecycle = JSON.parse(row.lifecycle_json) as Lifecycle;
    if (!lifecycle.expiresAt) throw new PanelFault('invalid_lifecycle', 422);
    if (row.final_snapshot_json) {
      const final = JSON.parse(row.final_snapshot_json) as Checkpoint;
      return { ...final, serverTime: Date.now(), expiresAt: lifecycle.expiresAt };
    }
    const snapshot = await this.storage.get<Checkpoint>(`snapshot:${row.panel_id}`);
    const checkpoint = snapshot?.definitionRevision === row.definition_revision ? snapshot : initialCheckpoint(row);
    const lease = await this.storage.get<Lease>(`lease:${row.panel_id}`);
    return { ...checkpoint, serverTime: Date.now(), expiresAt: lifecycle.expiresAt, leaseExpiresAt: lease ? new Date(lease.expiresAt).toISOString() : null };
  }

  private async renew(row: PanelRecord, body: unknown, key: string): Promise<unknown> {
    if (!key) throw new PanelFault('idempotency_key_required', 400);
    if (!isRecord(body) || body.protocolVersion !== 2 || Object.keys(body).some(k => !['protocolVersion', 'expectedMetadataVersion', 'expectedDefinitionRevision', 'ttlSeconds'].includes(k))) throw new PanelFault('invalid_command', 422);
    if (!Number.isInteger(body.expectedMetadataVersion) || Number(body.expectedMetadataVersion) < 1 || !Number.isInteger(body.expectedDefinitionRevision) || Number(body.expectedDefinitionRevision) < 1) throw new PanelFault('invalid_command', 422);
    const lifecycle = JSON.parse(row.lifecycle_json) as Lifecycle;
    const ttlSeconds = body.ttlSeconds ?? lifecycle.ttlSeconds ?? DEFAULT_TTL_SECONDS;
    if (typeof ttlSeconds !== 'number' || !Number.isInteger(ttlSeconds) || ttlSeconds < MIN_TTL_SECONDS || ttlSeconds > MAX_TTL_SECONDS) throw new PanelFault('invalid_lifecycle', 422);
    const hash = await bodyHash(body);
    const existing = await operationReceipt(this.db, row.panel_id, row.agent_id, key, hash);
    if (existing !== null) return existing;
    if (terminal(lifecycle.taskState)) throw new PanelFault('panel_ended');
    if (row.metadata_version !== body.expectedMetadataVersion || row.definition_revision !== body.expectedDefinitionRevision) throw new PanelFault('revision_conflict');
    const expiresAt = new Date(Date.now() + ttlSeconds * 1000).toISOString();
    const receipt = { operationId: crypto.randomUUID(), metadataVersion: row.metadata_version + 1, definitionRevision: row.definition_revision, ttlSeconds, expiresAt };
    const updatedLifecycle = { ...lifecycle, ttlSeconds, expiresAt };
    const guard = 'SELECT 1 FROM panels WHERE panel_id = ? AND last_operation_id = ?';
    const result = await this.db.batch([
      this.db.prepare('UPDATE panels SET lifecycle_json = ?, metadata_version = metadata_version + 1, last_operation_id = ? WHERE panel_id = ? AND metadata_version = ? AND definition_revision = ? AND agent_id = ? AND EXISTS (SELECT 1 FROM boss_agent_access ba WHERE ba.boss_id = panels.target_boss_id AND ba.agent_id = panels.agent_id)').bind(JSON.stringify(updatedLifecycle), receipt.operationId, row.panel_id, row.metadata_version, row.definition_revision, row.agent_id),
      this.db.prepare(`INSERT INTO panel_operations SELECT ?, ?, ?, ?, ?, ? WHERE EXISTS (${guard})`).bind(receipt.operationId, row.panel_id, row.agent_id, key, hash, JSON.stringify(receipt), row.panel_id, receipt.operationId),
      this.db.prepare(`INSERT INTO panel_outbox SELECT ?, ?, ?, ?, NULL WHERE EXISTS (${guard})`).bind(receipt.operationId, row.panel_id, row.metadata_version + 1, new Date().toISOString(), row.panel_id, receipt.operationId),
    ]);
    if (result[0].meta.changes !== 1) throw new PanelFault('revision_conflict');
    const snapshot = await this.storage.get<Checkpoint>(`snapshot:${row.panel_id}`);
    if (snapshot?.definitionRevision === row.definition_revision) await this.storage.put(`snapshot:${row.panel_id}`, { ...snapshot, expiresAt });
    this.broadcast(row.panel_id, { kind: 'panel.changed', panelId: row.panel_id, metadataVersion: receipt.metadataVersion });
    await this.wallChanged(row.panel_id, row.agent_id, expiresAt);
    return receipt;
  }

  private requireRunning(row: PanelRecord): Lifecycle {
    const lifecycle = JSON.parse(row.lifecycle_json) as Lifecycle;
    if (terminal(lifecycle.taskState)) throw new PanelFault('panel_ended');
    if (lifecycle.taskState !== 'running') throw new PanelFault('panel_paused');
    return lifecycle;
  }

  private async lease(row: PanelRecord, body: Record<string, unknown>): Promise<unknown> {
    this.requireRunning(row);
    if (body.definitionRevision !== row.definition_revision) throw new PanelFault('revision_conflict');
    const existing = await this.storage.get<Lease>(`lease:${row.panel_id}`);
    const now = Date.now();
    if (body.action === 'release') {
      if (!existing || body.epoch !== existing.epoch) throw new PanelFault('fenced_epoch');
      await this.storage.delete(`lease:${row.panel_id}`);
      return { kind: 'lease.release.ack', epoch: existing.epoch };
    }
    if (body.action === 'renew') {
      if (!existing || existing.expiresAt <= now || body.epoch !== existing.epoch) throw new PanelFault('fenced_epoch');
      const renewed = { ...existing, expiresAt: now + LEASE_MS };
      await this.storage.put(`lease:${row.panel_id}`, renewed);
      const state = await this.snapshot(row);
      this.broadcast(row.panel_id, { ...state, kind: 'state.observation' });
      return { kind: 'lease.ack', epoch: renewed.epoch, leaseExpiresAt: new Date(renewed.expiresAt).toISOString(), snapshot: state };
    }
    if (body.action !== 'claim' || typeof body.requestId !== 'string' || !body.requestId) throw new PanelFault('invalid_lease', 422);
    const hash = await bodyHash(body);
    if (existing?.requestId === body.requestId) {
      if (existing.hash !== hash) throw new PanelFault('idempotency_conflict');
      if (existing.expiresAt <= now) throw new PanelFault('lease_expired');
      return { kind: 'lease.ack', epoch: existing.epoch, leaseExpiresAt: new Date(existing.expiresAt).toISOString(), snapshot: await this.snapshot(row) };
    }
    if (existing && existing.expiresAt > now && body.takeoverEpoch !== existing.epoch) throw new PanelFault('lease_conflict');
    if (body.takeoverEpoch !== undefined && body.takeoverEpoch !== existing?.epoch) throw new PanelFault('fenced_epoch');
    const lease: Lease = { epoch: crypto.randomUUID(), expiresAt: now + LEASE_MS, requestId: body.requestId, hash };
    const baseline = { ...await this.snapshot(row), epoch: lease.epoch, sequence: 0, leaseExpiresAt: new Date(lease.expiresAt).toISOString() };
    await this.storage.put({ [`lease:${row.panel_id}`]: lease, [`snapshot:${row.panel_id}`]: baseline, [`receipts:${row.panel_id}`]: [] });
    this.broadcast(row.panel_id, { ...baseline, kind: 'state.snapshot' });
    return { kind: 'lease.ack', epoch: lease.epoch, leaseExpiresAt: new Date(lease.expiresAt).toISOString(), snapshot: baseline };
  }

  private async update(row: PanelRecord, body: Record<string, unknown>): Promise<unknown> {
    const lifecycle = this.requireRunning(row);
    const now = Date.now();
    const lease = await this.storage.get<Lease>(`lease:${row.panel_id}`);
    if (!lease || lease.expiresAt <= now || body.epoch !== lease.epoch) throw new PanelFault('fenced_epoch');
    if (body.definitionRevision !== row.definition_revision) throw new PanelFault('revision_conflict');
    if (typeof body.updateId !== 'string' || !body.updateId || body.updateId.length > 128) throw new PanelFault('invalid_update', 422);
    const hash = await bodyHash(body);
    const receipts = (await this.storage.get<UpdateReceipt[]>(`receipts:${row.panel_id}`) ?? []).filter(r => r.expiresAt > now);
    const previous = receipts.find(r => r.id === body.updateId);
    if (previous) {
      if (previous.hash !== hash) throw new PanelFault('idempotency_conflict');
      return previous.frame;
    }
    const snapshot = await this.snapshot(row);
    if (body.baseSequence !== snapshot.sequence) throw new PanelFault('resync_required');
    if (!['state.update', 'state.unchanged'].includes(String(body.kind))) throw new PanelFault('invalid_update', 422);
    const changed = body.kind === 'state.update';
    if (!changed && body.ops !== undefined && (!Array.isArray(body.ops) || body.ops.length)) throw new PanelFault('invalid_update', 422);
    const task = changed ? applyTaskPatch(snapshot.task, body.ops) : snapshot.task;
    validateTask(row, task);
    const next: Checkpoint = { ...snapshot, serverTime: now, task, sequence: snapshot.sequence + (changed ? 1 : 0), observationVersion: snapshot.observationVersion + 1,
      lastObservedAt: new Date(now).toISOString(), staleAt: new Date(now + Math.max(15, 2 * lifecycle.expectedUpdateIntervalSeconds) * 1000).toISOString(), expiresAt: snapshot.expiresAt, persistedAt: now };
    const frame = { ...next, kind: 'state.ack' };
    receipts.push({ id: body.updateId, hash, expiresAt: now + 600_000, frame });
    await this.storage.put({ [`snapshot:${row.panel_id}`]: next, [`receipts:${row.panel_id}`]: receipts.slice(-256) });
    this.broadcast(row.panel_id, { ...next, kind: changed ? 'state.patch' : 'state.observation', baseSequence: snapshot.sequence, ops: changed ? body.ops : undefined });
    return frame;
  }

  private async control(row: PanelRecord, agentId: string, value: unknown, key: string, action: 'lifecycle' | 'definition'): Promise<unknown> {
    if (!key) throw new PanelFault('idempotency_key_required', 400);
    const command = action === 'lifecycle' ? parseControl(value) : value;
    const hash = await bodyHash(command);
    const receipt = await operationReceipt(this.db, row.panel_id, agentId, key, hash);
    if (receipt !== null) return receipt;
    const existing = await this.storage.get<PendingControl>(`pending:${row.panel_id}`);
    if (existing) {
      if (existing.key !== key || existing.hash !== hash) throw new PanelFault('operation_pending');
      return this.finish(existing);
    }
    const lease = await this.storage.get<Lease>(`lease:${row.panel_id}`);
    const epoch = lease && lease.expiresAt > Date.now() ? lease.epoch : null;
    const snapshot = await this.snapshot(row);
    const pending = action === 'definition'
      ? await prepareDefinition(row, snapshot, agentId, key, command, epoch)
      : await prepareControl(row, snapshot, agentId, key, parseControl(command), epoch);
    await this.storage.transaction(async transaction => {
      await transaction.put(`pending:${row.panel_id}`, pending);
      await transaction.setAlarm(Math.min(await transaction.getAlarm() ?? Infinity, Date.now() + 5000));
    });
    return this.finish(pending);
  }

  private async finish(pending: PendingControl): Promise<unknown> {
    try {
      const receipt = await commitControl(this.db, pending);
      await this.storage.put(`snapshot:${pending.panelId}`, pending.snapshot);
      await this.storage.delete(`lease:${pending.panelId}`);
      this.broadcast(pending.panelId, { kind: 'panel.changed', panelId: pending.panelId, metadataVersion: pending.expectedVersion + 1 });
      if (!pending.lifecycle.expiresAt) throw new PanelFault('invalid_lifecycle', 422);
      await this.wallChanged(pending.panelId, pending.agentId, pending.lifecycle.expiresAt);
      await this.db.prepare('UPDATE panel_outbox SET delivered_at = ? WHERE event_id = ?').bind(new Date().toISOString(), pending.operationId).run();
      await this.storage.delete(`pending:${pending.panelId}`);
      return receipt;
    } catch (error) {
      if (error instanceof PanelFault && error.status !== 503) {
        await this.storage.delete([`lease:${pending.panelId}`, `pending:${pending.panelId}`]);
        throw error;
      }
      await this.storage.setAlarm(Math.min(await this.storage.getAlarm() ?? Infinity, Date.now() + 5000));
      return { status: 'pending', operationId: pending.operationId };
    }
  }

  private async recover(panelId: string): Promise<void> {
    const pending = await this.storage.get<PendingControl>(`pending:${panelId}`);
    if (!pending) return;
    const result = await this.finish(pending);
    if (isRecord(result) && result.status === 'pending') throw new PanelFault('operation_pending');
  }

  async repair(): Promise<void> {
    const pending = await this.storage.list<PendingControl>({ prefix: 'pending:' });
    for (const operation of pending.values()) {
      const previous = this.queues.get(operation.panelId) ?? Promise.resolve();
      const next = previous.catch(() => {}).then(() => this.finish(operation));
      this.queues.set(operation.panelId, next);
      try { await next; } catch { /* Rejected operations clear their durable fence. */ }
      finally { if (this.queues.get(operation.panelId) === next) this.queues.delete(operation.panelId); }
    }
  }
}
