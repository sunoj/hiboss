// Worker API tests for nickname allocation and additive session inventory fields.
// Exercises real D1 through registration, heartbeat, and both session lists.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, seedBossToken, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import { parseSessionNickname } from './session-nickname';

const OTHER_KEY = 'hb_test_key_nickname_other_0000';
const BOSS_TOKEN = 'hb_boss_nickname_inventory_0000';
interface Session {
  id: string;
  nickname: string | null;
  label: string;
  project_id: string;
  project_ref: { id: string; slug: string; display_name: string; avatar_url: string | null };
}

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('nickname-other-agent', 'nickname-other', await hashApiKey(OTHER_KEY)).run();
  await seedBossToken('Nickname inventory', 'admin', BOSS_TOKEN);
});

async function register(
  id: string, project: string, nickname?: string, other = false,
): Promise<Session> {
  const response = await SELF.fetch('http://localhost/api/sessions', {
    method: 'POST',
    headers: other ? { ...authHeaders(), Authorization: `Bearer ${OTHER_KEY}` } : authHeaders(),
    body: JSON.stringify({ id, project, branch: 'main', nickname }),
  });
  expect(response.status).toBe(201);
  return response.json() as Promise<Session>;
}

async function heartbeat(id: string, nickname?: string): Promise<string | null> {
  const response = await SELF.fetch(`http://localhost/api/sessions/${id}`, {
    method: 'PATCH', headers: authHeaders(), body: JSON.stringify({ nickname, status: 'working' }),
  });
  expect(response.status).toBe(200);
  return (await response.json() as { nickname: string | null }).nickname;
}

describe('CLI-selected nickname allocation', () => {
  it('suffixes collisions across agents in the same project and preserves accepted names', async () => {
    expect((await register('nick-first', 'nick-collision', 'coral')).nickname).toBe('coral');
    expect((await register('nick-second', 'nick-collision', 'coral', true)).nickname).toBe('coral-2');
    expect((await register('nick-third', 'nick-collision', 'coral')).nickname).toBe('coral-3');
    expect((await register('nick-third', 'nick-collision', 'palm')).nickname).toBe('coral-3');
    expect(await heartbeat('nick-third', 'coral')).toBe('coral-3');
    expect((await register('nick-elsewhere', 'nick-other-project', 'coral')).nickname).toBe('coral');
  });

  it('keeps concurrent registrations unique', async () => {
    const rows = await Promise.all(Array.from({ length: 8 }, (_, index) =>
      register(`nick-race-${index}`, 'nick-race-project', 'otter')));
    const names = rows.map(row => row.nickname);
    expect(new Set(names).size).toBe(8);
    expect(names).toEqual(expect.arrayContaining([
      'otter', 'otter-2', 'otter-3', 'otter-4', 'otter-5', 'otter-6', 'otter-7', 'otter-8',
    ]));
  });

  it('reuses completed and old names and resolves a collision when an old session resumes', async () => {
    await register('nick-done', 'nick-reuse', 'reef');
    await env.DB.prepare("UPDATE sessions SET status = 'completed' WHERE id = 'nick-done'").run();
    expect((await register('nick-replacement', 'nick-reuse', 'reef')).nickname).toBe('reef');
    expect(await heartbeat('nick-done', 'reef')).toBe('reef-2');
    await env.DB.prepare(`UPDATE sessions SET last_seen_at = datetime('now', '-25 hours')
      WHERE id IN ('nick-done', 'nick-replacement')`).run();
    expect((await register('nick-new-live', 'nick-reuse', 'reef')).nickname).toBe('reef');
    expect(await heartbeat('nick-replacement', 'reef')).toBe('reef-2');
    expect(await heartbeat('nick-done', 'reef-2')).toBe('reef-3');
  });

});

describe('nickname upgrades and validation', () => {
  it('adds names on the next upgraded heartbeat or registration without requiring old clients to send one',
    async () => {
      expect((await register('nick-legacy-heartbeat', 'nick-legacy')).nickname).toBeNull();
      expect(await heartbeat('nick-legacy-heartbeat', 'gull')).toBe('gull');
      await register('nick-legacy-register', 'nick-legacy');
      expect((await register('nick-legacy-register', 'nick-legacy', 'gull')).nickname).toBe('gull-2');
      expect(await heartbeat('nick-legacy-heartbeat')).toBe('gull');
    });

  it('rejects malformed nicknames at registration and heartbeat', async () => {
    await register('nick-validation', 'nick-validation');
    for (const nickname of ['ab', 'Coral', 'coral-1', 'coral-02', 'two words', 'a'.repeat(13), 7]) {
      for (const [method, path] of [['POST', '/api/sessions'], ['PATCH', '/api/sessions/nick-validation']]) {
        const response = await SELF.fetch(`http://localhost${path}`, {
          method, headers: authHeaders(),
          body: JSON.stringify({ id: 'nick-validation', project: 'nick-validation', nickname }),
        });
        expect(response.status, `${method}: ${nickname}`).toBe(400);
      }
    }
    expect(parseSessionNickname(undefined)).toBeNull();
    expect(parseSessionNickname(null)).toBeNull();
    expect(parseSessionNickname('coral-10')).toBe('coral-10');
  });
});

describe('session inventory fields', () => {
  it('returns nickname and project avatars to agents and bosses, with null for unset avatars', async () => {
    const named = await register('nick-inventory', 'nick-inventory', 'lagoon');
    const plain = await register('nick-no-avatar', 'nick-no-avatar');
    const avatar = 'https://images.example.test/project.png';
    await env.DB.prepare('UPDATE projects SET avatar_url = ? WHERE id = ?')
      .bind(avatar, named.project_id).run();
    for (const [path, headers] of [
      ['/api/sessions', authHeaders()],
      ['/api/boss/sessions', { Authorization: `Bearer ${BOSS_TOKEN}` }],
    ] as const) {
      const response = await SELF.fetch(`http://localhost${path}`, { headers });
      expect(response.status).toBe(200);
      const { sessions } = await response.json() as { sessions: Session[] };
      expect(sessions.find(row => row.id === named.id)).toMatchObject({
        nickname: 'lagoon', label: 'nick-inventory/main',
        project_ref: { ...named.project_ref, avatar_url: avatar },
      });
      expect(sessions.find(row => row.id === plain.id)).toMatchObject({
        nickname: null, project_ref: { avatar_url: null },
      });
    }
  });
});
