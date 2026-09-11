// Lifecycle wire contracts and shared defaults for native cards and producers.
// Exports lifecycle, preference, checkpoint, command, and error types.
// Dependencies: panel definition JSON types; no transport dependencies.

import type { JsonValue } from '../definition/types';

export type PanelId = string & { readonly __panelId: unique symbol };
export type TaskState = 'running' | 'paused' | 'completed' | 'failed' | 'cancelled';
export const DEFAULT_TTL_SECONDS = 3600;
export const MIN_TTL_SECONDS = 60;
export const MAX_TTL_SECONDS = 604800;
export interface Lifecycle {
  taskState: TaskState;
  mode: 'run' | 'monitor';
  expectedUpdateIntervalSeconds: number;
  ttlSeconds: number;
  lastObservedAt: string | null;
  expiresAt?: string;
  terminalAt: string | null;
  dismissAt: string | null;
  dismissalPolicy: 'after' | 'immediate' | 'manual' | null;
  result: { title: string; message?: string; code?: string } | null;
}
export interface Preference {
  preferenceVersion: number;
  placement: 'automatic' | 'pinned' | 'archived';
  seenTerminalVersion: number | null;
  acknowledgedTerminalVersion: number | null;
}
export interface Checkpoint {
  protocolVersion: 2;
  serverTime: number;
  panelId: string;
  definitionRevision: number;
  epoch: string | null;
  sequence: number;
  task: JsonValue;
  observationVersion: number;
  lastObservedAt: string | null;
  staleAt: string | null;
  expiresAt: string;
  leaseExpiresAt: string | null;
  persistedAt: number;
}
export interface ControlCommand {
  protocolVersion: 2;
  action: 'pause' | 'resume' | 'complete' | 'fail' | 'cancel';
  expectedMetadataVersion: number;
  expectedDefinitionRevision: number;
  expectedEpoch: string | null;
  expectedState: { epoch: string | null; sequence: number } | null;
  openRequests: 'reject' | 'withdraw';
  withdrawalReason?: string;
  dismissal?: { policy: 'default' | 'immediate' | 'after' | 'manual'; afterSeconds?: number };
  finalTask?: JsonValue;
  result?: { title: string; message?: string; code?: string };
}
export const defaultLifecycle = (): Lifecycle => ({ taskState: 'running', mode: 'run', expectedUpdateIntervalSeconds: 15, ttlSeconds: DEFAULT_TTL_SECONDS, lastObservedAt: null, terminalAt: null, dismissAt: null, dismissalPolicy: null, result: null });
export const defaultPreference = (): Preference => ({ preferenceVersion: 0, placement: 'automatic', seenTerminalVersion: null, acknowledgedTerminalVersion: null });
export const terminal = (state: TaskState): boolean => ['completed', 'failed', 'cancelled'].includes(state);
export const LEASE_MS = 45_000;
export class PanelFault extends Error {
  constructor(readonly code: string, readonly status: 400 | 403 | 404 | 409 | 422 | 503 = 409, message = code) { super(message); }
}
export function faultResponse(error: unknown): Response {
  const fault = error instanceof PanelFault ? error : new PanelFault('service_unavailable', 503);
  return Response.json({ error: { code: fault.code, message: fault.message, retryable: fault.status === 503 } }, { status: fault.status });
}
