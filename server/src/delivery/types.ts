// Contracts for boss destination resolution and delivery scheduling.
// Exports branded destination IDs and typed D1 rows; depends on shared message types.
import type { MessageRow, Priority } from '../types';

export type DestinationId = string & { readonly __brand: 'DestinationId' };
export type DestinationsMode = 'off' | 'shadow' | 'on';
export type DestinationKind = 'telegram_chat' | 'discord_channel' | 'apns' | 'native_live';
export type DestinationMessage = Pick<MessageRow, 'agent_id' | 'priority' | 'session_id' | 'direction'> & { project?: string | null };
export interface DestinationRow {
  id: DestinationId;
  boss_id: string;
  kind: DestinationKind;
  client_id: string | null;
  provider_id: string | null;
  target: string;
  credentials: string | null;
  preferences: string | null;
  min_priority: Priority;
  enabled: number;
  honours_quiet_hours: number;
  quiet_start: string | null;
  quiet_end: string | null;
  timezone: string | null;
  quiet_enabled: number | null;
}
export interface ResolvedDestination extends DestinationRow {
  config: Record<string, unknown>;
  nextAttemptAt: string | null;
}
export interface RouteRow {
  external_channel_id: string | null;
  external_thread_id: string | null;
}
export const PRIORITY_RANK: Record<Priority, number> = { low: 0, normal: 1, high: 2, critical: 3 };

export function destinationsMode(value: string | undefined): DestinationsMode {
  return value === 'shadow' || value === 'on' ? value : 'off';
}

export function jsonObject(value: string | null): Record<string, unknown> {
  try {
    const parsed: unknown = JSON.parse(value ?? '{}');
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed as Record<string, unknown> : {};
  } catch { return {}; }
}
