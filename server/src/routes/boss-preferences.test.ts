// Tests for boss notification preference validation and routing defaults.
// Covers schema errors, default no-routing behavior, and D1 routing lookup.
// Depends on cloudflare:test fixtures and boss-preferences helpers.

import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase } from '../test-helpers';
import {
  DEFAULT_BOSS_PREFERENCES,
  parseBossPreferences,
  resolveBossRoutingChannels,
  validateBossPreferences,
} from './boss-preferences';

beforeAll(async () => {
  await seedDatabase();
});

describe('validateBossPreferences', () => {
  it('keeps default preferences from opting into routing', () => {
    expect('routing' in DEFAULT_BOSS_PREFERENCES).toBe(false);
    expect(DEFAULT_BOSS_PREFERENCES.quiet_hours).toBeNull();
  });

  it('accepts routing and quiet-hours preferences', () => {
    const result = validateBossPreferences({
      routing: { critical: ['discord', 'api'], normal: ['telegram'] },
      quiet_hours: {
        enabled: true,
        start: '22:00',
        end: '08:00',
        timezone: 'Asia/Bangkok',
        days: [1, 2, 3, 4, 5],
        critical_bypass: true,
      },
    });

    expect(result.ok).toBe(true);
  });

  it('rejects unknown routing priority keys', () => {
    const result = validateBossPreferences({ routing: { urgent: ['api'] } });

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain('routing keys');
  });

  it('rejects unknown routing channels', () => {
    const result = validateBossPreferences({ routing: { normal: ['email'] } });

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain('discord, telegram, or api');
  });
});

describe('parseBossPreferences', () => {
  it('returns null for invalid stored JSON', () => {
    expect(parseBossPreferences('{bad-json')).toBeNull();
  });
});

describe('resolveBossRoutingChannels', () => {
  it('returns not_configured when no boss has routing', async () => {
    await seedBossPreference('boss-pref-no-routing-agent', 'boss-pref-no-routing', { quiet_hours: null });

    await expect(resolveBossRoutingChannels(env, 'boss-pref-no-routing-agent', 'normal'))
      .resolves.toEqual({ kind: 'not_configured' });
  });

  it('returns not_configured when only another priority is present', async () => {
    await seedBossPreference('boss-pref-critical-only-agent', 'boss-pref-critical-only', {
      routing: { critical: ['discord'] },
    });

    await expect(resolveBossRoutingChannels(env, 'boss-pref-critical-only-agent', 'normal'))
      .resolves.toEqual({ kind: 'not_configured' });
  });

  it('returns muted for an explicit empty priority array', async () => {
    await seedBossPreference('boss-pref-muted-agent', 'boss-pref-muted', {
      routing: { normal: [] },
    });

    await expect(resolveBossRoutingChannels(env, 'boss-pref-muted-agent', 'normal'))
      .resolves.toEqual({ kind: 'muted' });
  });

  it('returns configured channels for the requested priority', async () => {
    await seedBossPreference('boss-pref-routing-agent', 'boss-pref-routing', {
      routing: { normal: ['discord', 'api'] },
    });

    await expect(resolveBossRoutingChannels(env, 'boss-pref-routing-agent', 'normal'))
      .resolves.toEqual({ kind: 'channels', channels: ['discord', 'api'] });
  });

  it('unions channels across bosses and ignores missing priority keys', async () => {
    await seedBossPreference('boss-pref-multi-agent', 'boss-pref-multi-critical', {
      routing: { critical: ['api'] },
    });
    await seedBossPreference('boss-pref-multi-agent', 'boss-pref-multi-normal', {
      routing: { normal: ['telegram'] },
    });

    await expect(resolveBossRoutingChannels(env, 'boss-pref-multi-agent', 'normal'))
      .resolves.toEqual({ kind: 'channels', channels: ['telegram'] });
  });

  it('keeps an explicit mute when another boss omits the priority', async () => {
    await seedBossPreference('boss-pref-multi-muted-agent', 'boss-pref-multi-muted-critical', {
      routing: { critical: ['api'] },
    });
    await seedBossPreference('boss-pref-multi-muted-agent', 'boss-pref-multi-muted-normal', {
      routing: { normal: [] },
    });

    await expect(resolveBossRoutingChannels(env, 'boss-pref-multi-muted-agent', 'normal'))
      .resolves.toEqual({ kind: 'muted' });
  });
});

async function seedBossPreference(
  agentId: string,
  bossId: string,
  preferences: Record<string, unknown>,
): Promise<void> {
  await env.DB.prepare('INSERT OR REPLACE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agentId, agentId, `${agentId}-hash`)
    .run();
  await env.DB.prepare(
    'INSERT OR REPLACE INTO bosses (id, name, role, preferences) VALUES (?, ?, ?, ?)'
  ).bind(bossId, `Boss ${bossId}`, 'manager', JSON.stringify(preferences)).run();
  await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, agentId)
    .run();
}
