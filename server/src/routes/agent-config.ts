// Agent self-configuration validation, keeping workflow roles separate from admin capability.
// Exports agentConfigUpdates; depends on domain channels and priorities.
import type { Channel, Priority } from '../types';
type Bind = string | number | null;
interface Updates { updates: string[]; binds: Bind[] }
const VALID_PRIORITIES: Priority[] = ['critical', 'high', 'normal', 'low'];
export function agentConfigUpdates(payload: Record<string, unknown>):
  | { ok: true; value: Updates } | { ok: false; error: string } {
  const value: Updates = { updates: [], binds: [] };
  const error = deliveryUpdates(payload, value) ?? profileUpdates(payload, value);
  return error ? { ok: false, error } : { ok: true, value };
}
function deliveryUpdates(payload: Record<string, unknown>, { updates, binds }: Updates): string | null {
  if ('default_priority' in payload) {
    const dp = payload.default_priority;
    if (typeof dp !== 'string' || !VALID_PRIORITIES.includes(dp as Priority)) {
      return 'invalid default_priority';
    }
    updates.push('default_priority = ?');
    binds.push(dp);
  }
  if ('rate_limit' in payload) {
    const rl = payload.rate_limit;
    if (rl !== null && (typeof rl !== 'number' || rl < 0 || !Number.isInteger(rl))) {
      return 'rate_limit must be a positive integer or null';
    }
    updates.push('rate_limit = ?');
    binds.push(rl);
  }
  if ('channel_routing' in payload) {
    const cr = payload.channel_routing;
    if (cr === null) {
      updates.push('channel_routing = NULL');
    } else if (typeof cr === 'object' && !Array.isArray(cr)) {
      const validChannels: Channel[] = ['discord', 'telegram', 'email'];
      for (const [, ch] of Object.entries(cr as Record<string, unknown>)) {
        if (typeof ch !== 'string' || !validChannels.includes(ch as Channel)) {
          return 'channel_routing values must be valid channels';
        }
      }
      updates.push('channel_routing = ?');
      binds.push(JSON.stringify(cr));
    } else {
      return 'channel_routing must be an object or null';
    }
  }
  return null;
}

function profileUpdates(payload: Record<string, unknown>, { updates, binds }: Updates): string | null {
  if ('avatar_url' in payload) {
    const av = payload.avatar_url;
    if (av === null) {
      updates.push('avatar_url = NULL');
    } else if (typeof av === 'string') {
      updates.push('avatar_url = ?');
      binds.push(av);
    } else {
      return 'avatar_url must be a string or null';
    }
  }
  if ('role' in payload) {
    const role = payload.role;
    const validRoles = ['orchestrator', 'worker', 'reviewer'];
    if (role === null) {
      updates.push('role = NULL');
    } else if (typeof role === 'string' && validRoles.includes(role)) {
      updates.push('role = ?');
      binds.push(role);
    } else {
      return 'role must be orchestrator, worker, or reviewer';
    }
  }
  if ('session_info' in payload) {
    const si = payload.session_info;
    if (si === null) {
      updates.push('session_info = NULL');
    } else if (typeof si === 'object' && !Array.isArray(si)) {
      updates.push('session_info = ?');
      binds.push(JSON.stringify(si));
    } else {
      return 'session_info must be an object or null';
    }
  }
  return null;
}
