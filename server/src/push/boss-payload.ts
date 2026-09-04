// Builds boss APNs payloads and applies per-boss delivery preferences.
// Exports: prepareBossPush and its session/result contracts.
// Dependencies: message snapshots, APNs delivery types, and message priorities.

import type {
  ApnsInterruptionLevel,
  ApnsPayload,
  ApnsPriority,
} from '../apns';
import type { MessageRow, Priority } from '../types';
import { attachMessageSnapshot } from './message-snapshot';

export interface BossPushSession {
  readonly label: string | null;
  readonly branch: string | null;
}

export interface PreparedBossPush {
  readonly payload: ApnsPayload;
  readonly apnsPriority: ApnsPriority;
}

interface PushTier {
  readonly deliver: boolean;
  readonly sound: boolean;
  readonly level: ApnsInterruptionLevel;
  readonly apnsPriority: ApnsPriority;
}

interface PushPreferenceOverride {
  readonly deliver?: boolean;
  readonly sound?: boolean;
  readonly level?: 'passive' | 'active' | 'time-sensitive' | 'critical';
}

export function prepareBossPush(
  message: MessageRow,
  agentName: string,
  session: BossPushSession | null,
  bossId: string,
  preferences: string | null | undefined,
): PreparedBossPush | null {
  const options = extractOptions(message.metadata);
  const isDecision = options !== undefined && options.length > 0;
  const effectiveDecision = isDecision && decisionAlertsEnabled(preferences);
  const tier = pushTier(message.priority, effectiveDecision, preferences);
  if (!tier.deliver) return null;
  const privatePush = isPrivatePush(preferences);
  const payload = buildPayload(message, agentName, session, bossId, tier, privatePush, options);
  return { payload, apnsPriority: tier.apnsPriority };
}

function buildPayload(
  message: MessageRow,
  agentName: string,
  session: BossPushSession | null,
  bossId: string,
  tier: PushTier,
  privatePush: boolean,
  options: string[] | undefined,
): ApnsPayload {
  const projectLabel = session?.label ?? session?.branch ?? null;
  const category = privatePush ? 'HIBOSS_MESSAGE' : (options ? 'HIBOSS_OPTIONS' : 'HIBOSS_MESSAGE');
  const alert = buildAlert(message, agentName, projectLabel, privatePush, options !== undefined);
  const aps: ApnsPayload['aps'] = {
    alert,
    'interruption-level': tier.level,
    'thread-id': bossId,
    category,
  };
  if (tier.sound) aps.sound = 'default';
  const payload: ApnsPayload = {
    aps,
    messageId: message.id,
    agentName,
    priority: message.priority,
    direction: message.direction,
    category,
  };
  if (options && !privatePush) payload.options = options;
  if (privatePush) return payload;
  return attachMessageSnapshot(payload, message, {
    agentName,
    sessionLabel: session?.label ?? null,
    sessionBranch: session?.branch ?? null,
  });
}

function buildAlert(
  message: MessageRow,
  agentName: string,
  projectLabel: string | null,
  privatePush: boolean,
  isDecision: boolean,
): ApnsPayload['aps']['alert'] {
  const summary = extractText(message.metadata, 'summary');
  const body = privatePush
    ? (summary ?? (isDecision ? `New decision from ${agentName}` : `New message from ${agentName}`))
    : normalPushBody(message.body, agentName, projectLabel);
  const alert: ApnsPayload['aps']['alert'] = {
    title: privatePush ? 'HiBoss' : (projectLabel || agentName || 'HiBoss'),
    body,
  };
  const content = extractText(message.metadata, 'content');
  if (!privatePush && content) alert.subtitle = truncate(content, 120);
  return alert;
}

function extractText(metadata: string | null, key: 'summary' | 'content'): string | undefined {
  if (!metadata) return undefined;
  try {
    const parsed = JSON.parse(metadata) as Record<string, unknown>;
    const text = typeof parsed[key] === 'string' ? parsed[key].trim() : '';
    return text.length > 0 ? text : undefined;
  } catch {
    return undefined;
  }
}

function extractOptions(metadata: string | null): string[] | undefined {
  if (!metadata) return undefined;
  try {
    const parsed = JSON.parse(metadata) as unknown;
    if (!parsed || typeof parsed !== 'object') return undefined;
    const options = (parsed as { options?: unknown }).options;
    return Array.isArray(options) && options.every((option): option is string => typeof option === 'string')
      ? options
      : undefined;
  } catch {
    return undefined;
  }
}

function isPrivatePush(preferences: string | null | undefined): boolean {
  return readPreferences(preferences)?.private_push === true;
}

function decisionAlertsEnabled(preferences: string | null | undefined): boolean {
  return readPreferences(preferences)?.decision_alerts !== false;
}

function readPreferences(preferences: string | null | undefined): Record<string, unknown> | null {
  if (!preferences) return null;
  try {
    return JSON.parse(preferences) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function pushTier(priority: Priority, isDecision: boolean, preferences: string | null | undefined): PushTier {
  if (isDecision) {
    return priority === 'critical'
      ? { deliver: true, sound: true, level: 'time-sensitive', apnsPriority: '10' }
      : { deliver: true, sound: true, level: 'active', apnsPriority: '10' };
  }
  const base = defaultStatusPushTier(priority);
  const override = statusPushOverride(priority, preferences);
  if (!override) return base;
  const sound = override.sound ?? base.sound;
  const level = normalizeInterruptionLevel(override.level ?? base.level);
  return {
    deliver: override.deliver ?? base.deliver,
    sound,
    level,
    apnsPriority: apnsPriorityFor(sound, level),
  };
}

function defaultStatusPushTier(priority: Priority): PushTier {
  switch (priority) {
    case 'critical':
      return { deliver: true, sound: true, level: 'time-sensitive', apnsPriority: '10' };
    case 'high':
      return { deliver: true, sound: true, level: 'active', apnsPriority: '10' };
    case 'normal':
      return { deliver: true, sound: false, level: 'passive', apnsPriority: '5' };
    case 'low':
      return { deliver: false, sound: false, level: 'passive', apnsPriority: '5' };
    default:
      return { deliver: true, sound: false, level: 'passive', apnsPriority: '5' };
  }
}

function statusPushOverride(
  priority: Priority,
  preferences: string | null | undefined,
): PushPreferenceOverride | null {
  const push = readPreferences(preferences)?.push;
  if (!push || typeof push !== 'object' || Array.isArray(push)) return null;
  const value = (push as Record<string, unknown>)[priority];
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  return {
    deliver: typeof raw.deliver === 'boolean' ? raw.deliver : undefined,
    sound: typeof raw.sound === 'boolean' ? raw.sound : undefined,
    level: pushLevel(raw.level),
  };
}

function pushLevel(value: unknown): PushPreferenceOverride['level'] {
  return value === 'passive' || value === 'active' || value === 'time-sensitive' || value === 'critical'
    ? value
    : undefined;
}

function normalizeInterruptionLevel(level: PushPreferenceOverride['level']): ApnsInterruptionLevel {
  return level === 'critical' ? 'time-sensitive' : level ?? 'passive';
}

function apnsPriorityFor(sound: boolean, level: ApnsInterruptionLevel): ApnsPriority {
  return sound || level === 'active' || level === 'time-sensitive' ? '10' : '5';
}

function normalPushBody(body: string, agentName: string, projectLabel: string | null): string {
  const truncatedBody = truncate(body, 150);
  return projectLabel && agentName !== projectLabel ? `${agentName} · ${truncatedBody}` : truncatedBody;
}

function truncate(value: string, limit: number): string {
  return value.length > limit ? `${value.slice(0, limit - 3)}...` : value;
}
