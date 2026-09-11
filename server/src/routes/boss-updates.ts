// Builds atomic admin boss updates while synchronizing external identities.
// Exports buildBossUpdate; depends on typed boss rows, validation, and D1 helpers.
import type { Env } from '../types';
import type { BossRow } from './bosses';
import { validatePreferences } from './boss-preferences';
import { identityConflict, legacyIdentityWrites } from './boss-external-accounts';
type Update = { columns: string[]; values: (string | null)[]; writes: D1PreparedStatement[] };
type Result = { ok: true; writes: D1PreparedStatement[] } | { ok: false; error: string; status: 400 | 409 };
export async function buildBossUpdate(env: Env, boss: BossRow, payload: Record<string, unknown>): Promise<Result> {
  const update: Update = { columns: [], values: [], writes: [] };
  const error = simpleFields(payload, update) ?? preferenceFields(boss, payload, update);
  if (error) return { ok: false, error, status: 400 };
  for (const provider of ['telegram', 'discord'] as const) {
    const key = provider === 'telegram' ? 'telegram_user_id' : 'discord_user_id';
    if (!(key in payload)) continue;
    const input = payload[key];
    if (input !== null && typeof input !== 'string') return { ok: false, error: `${key} must be a string or null`, status: 400 };
    const value = typeof input === 'string' ? input.trim() || null : null;
    if (value && await identityConflict(env, boss.id, provider, value)) return { ok: false, error: 'external account already linked', status: 409 };
    update.columns.push(`${key} = ?`); update.values.push(value);
    update.writes.push(...legacyIdentityWrites(env, boss.id, provider, boss[key], value));
  }
  if (!update.columns.length) return { ok: false, error: 'no valid fields to update', status: 400 };
  return { ok: true, writes: [env.DB.prepare(`UPDATE bosses SET ${update.columns.join(', ')} WHERE id = ?`)
    .bind(...update.values, boss.id), ...update.writes] };
}
function simpleFields(payload: Record<string, unknown>, update: Update): string | null {
  for (const key of ['name', 'role', 'agent_id']) {
    if (!(key in payload)) continue;
    const input = payload[key];
    if (key === 'agent_id' && input === null) { update.columns.push(`${key} = ?`); update.values.push(null); continue; }
    if (typeof input !== 'string') return `${key} must be a string`;
    const value = input.trim();
    if (key === 'name' && !value) return 'name is required';
    if (key === 'role' && !['admin', 'manager', 'viewer'].includes(value)) return 'invalid role';
    update.columns.push(`${key} = ?`); update.values.push(value || null);
  }
  return null;
}
function preferenceFields(boss: BossRow, payload: Record<string, unknown>, update: Update): string | null {
  if (!('preferences' in payload)) return null;
  const prefs = payload.preferences;
  if (prefs === null) { update.columns.push('preferences = ?'); update.values.push(null); return null; }
  if (!prefs || typeof prefs !== 'object' || Array.isArray(prefs)) return 'preferences must be an object or null';
  const error = validatePreferences(prefs as Record<string, unknown>);
  if (error) return error;
  const existing: Record<string, unknown> = boss.preferences ? JSON.parse(boss.preferences) : {};
  const { preferred_channel: _channel, notify_priorities: _priorities, ...retained } = existing;
  update.columns.push('preferences = ?'); update.values.push(JSON.stringify({ ...retained, ...prefs }));
  return null;
}
