// Builds atomic admin boss updates while synchronizing external identities.
// Exports buildBossUpdate; depends on typed boss rows, validation, and D1 helpers.
import type { Env } from '../types';
import type { BossRow } from './bosses';
import { validatePreferences } from './boss-preferences';
import { legacyIdentityWrites } from './boss-external-accounts';
type Update = { columns: string[]; values: (string | null)[]; writes: D1PreparedStatement[] };
type Result = { ok: true; writes: D1PreparedStatement[] } | { ok: false; error: string; status: 400 };
export async function buildBossUpdate(env: Env, boss: BossRow, payload: Record<string, unknown>): Promise<Result> {
  const update: Update = { columns: [], values: [], writes: [] };
  const error = simpleFields(payload, update);
  if (error) return { ok: false, error, status: 400 };
  for (const key of ['telegram_user_id', 'discord_user_id', 'agent_id'] as const) {
    if (!(key in payload)) continue;
    const input = payload[key];
    if (input !== null && typeof input !== 'string') return { ok: false, error: `${key} must be a string or null`, status: 400 };
    const value = typeof input === 'string' ? input.trim() || null : null;
    update.columns.push(`${key} = ?`); update.values.push(value);
    if (key !== 'agent_id') {
      const provider = key === 'telegram_user_id' ? 'telegram' : 'discord';
      update.writes.push(...legacyIdentityWrites(env, boss.id, provider, boss[key], value));
    }
  }
  const preferenceError = preferenceFields(boss, payload, update);
  if (preferenceError) return { ok: false, error: preferenceError, status: 400 };
  if (!update.columns.length) return { ok: false, error: 'no valid fields to update', status: 400 };
  return { ok: true, writes: [env.DB.prepare(`UPDATE bosses SET ${update.columns.join(', ')} WHERE id = ?`)
    .bind(...update.values, boss.id), ...update.writes] };
}
function simpleFields(payload: Record<string, unknown>, update: Update): string | null {
  for (const key of ['name', 'role']) {
    if (!(key in payload)) continue;
    const input = payload[key];
    if (typeof input !== 'string') continue;
    const value = key === 'name' ? input.trim() : input;
    if (key === 'name' && !value) return 'name is required';
    if (key === 'role' && !['admin', 'manager', 'viewer'].includes(value)) return 'invalid role';
    update.columns.push(`${key} = ?`); update.values.push(value);
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
  let existing: Record<string, unknown> = {};
  try { existing = boss.preferences ? JSON.parse(boss.preferences) ?? {} : {}; } catch { /* Match the parent safe parser. */ }
  const { preferred_channel: _channel, notify_priorities: _priorities, ...retained } = existing;
  update.columns.push('preferences = ?'); update.values.push(JSON.stringify({ ...retained, ...prefs }));
  return null;
}
