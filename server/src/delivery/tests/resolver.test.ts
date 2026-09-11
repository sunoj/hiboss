// Resolver truth tables and D1 access/thread lookup against isolated fixtures.
// Depends on the pure destination policy, actual D1 resolver, and shared test seeding.
import { env } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { seedDatabase } from '../../test-helpers';
import { destinationQuietEnd, eligibleDestination, resolveDestinations } from '../destinations';
import { PRIORITY_RANK, type DestinationRow, type DestinationId } from '../types';
import type { Priority } from '../../types';

const now = new Date('2026-09-11T02:00:00Z');
const base: DestinationRow = {
  id: 'destination' as DestinationId, boss_id: 'boss', kind: 'telegram_chat', client_id: null,
  target: '{}', credentials: '{}', preferences: null, min_priority: 'low', enabled: 1,
  honours_quiet_hours: 1, quiet_start: '22:00', quiet_end: '08:00', timezone: 'UTC', quiet_enabled: 1,
};
const priorities = Object.keys(PRIORITY_RANK) as Priority[];
for (const priority of priorities) for (const min of priorities) for (const enabled of [0, 1]) {
  it(`priority ${priority}, minimum ${min}, enabled ${enabled}`, () => {
    const message = { agent_id: 'agent', priority, direction: 'agent_to_boss' as const, session_id: null };
    expect(eligibleDestination({ ...base, min_priority: min, enabled }, message))
      .toBe(enabled === 1 && PRIORITY_RANK[priority] >= PRIORITY_RANK[min]);
    expect(eligibleDestination(base, { ...message, direction: 'boss_to_agent' })).toBe(false);
  });
}
for (const priority of priorities) for (const honours of [0, 1]) for (const quiet of [0, 1]) {
  it(`quiet hours priority ${priority}, honours ${honours}, enabled ${quiet}`, () => {
    const row = { ...base, honours_quiet_hours: honours, quiet_enabled: quiet };
    const deferred = honours && quiet && (priority === 'normal' || priority === 'low');
    expect(destinationQuietEnd(row, priority, now)).toBe(deferred ? '2026-09-11T08:00:00.000Z' : null);
    expect(destinationQuietEnd(row, priority, new Date('2026-09-11T12:00:00Z'))).toBeNull();
  });
}

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, credentials, label) VALUES ('rp', 'telegram', '{\"bot_token\":\"token\"}', 'Bot')").run();
  await env.DB.prepare("INSERT INTO sessions (id, agent_id, label) VALUES ('rs', 'test-agent-id', 'project/branch')").run();
});

for (const role of ['admin', 'manager', 'viewer']) for (const granted of [false, true]) {
  it(`resolves ${role} with explicit grant ${granted} and session precedence`, async () => {
    const id = `${role}-${granted}`;
    await env.DB.prepare('INSERT INTO bosses (id, name, role) VALUES (?, ?, ?)').bind(id, id, role).run();
    if (granted) await env.DB.prepare("INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, 'test-agent-id')").bind(id).run();
    await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label) VALUES (?, ?, 'telegram_chat', 'rp', '{\"chat_id\":\"123\"}', 'Chat')").bind(id, id).run();
    await env.DB.prepare("INSERT INTO destination_routes (destination_id, project, external_thread_id) VALUES (?, 'project', '10')").bind(id).run();
    await env.DB.prepare("INSERT INTO destination_routes (destination_id, session_id, external_thread_id) VALUES (?, 'rs', '20')").bind(id).run();
    const message = { agent_id: 'test-agent-id', priority: 'normal' as const, direction: 'agent_to_boss' as const, session_id: 'rs' };
    const resolved = (await resolveDestinations(env, message, now)).find(row => row.id === id);
    expect(Boolean(resolved)).toBe(role === 'admin' || granted);
    if (resolved) {
      expect(resolved.config.message_thread_id).toBe(20);
      const project = (await resolveDestinations(env, { ...message, session_id: null, project: 'project' }, now)).find(row => row.id === id);
      expect(project?.config.message_thread_id).toBe(10);
    }
  });
}
