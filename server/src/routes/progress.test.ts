// Integration tests for the progress feed API and its visibility boundaries.
// Covers posting, validation, cursors, projects, deletion, and dual-auth scope.
// Depends on cloudflare:test, the progress router, and shared database seeding.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { hashApiKey } from '../middleware/auth';
import { authHeaders, getTestAgentId, seedDatabase } from '../test-helpers';

const BOSS_TOKEN = 'hb_progress_boss_token_0000000000000001';
const OTHER_AGENT_ID = 'progress-other-agent';

function bossHeaders(): Record<string, string> {
  return { Authorization: `Bearer ${BOSS_TOKEN}`, 'Content-Type': 'application/json' };
}

async function createProgressSchema(): Promise<void> {
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS progress_posts (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    agent_id TEXT NOT NULL REFERENCES api_keys(id),
    session_id TEXT,
    project TEXT NOT NULL,
    body TEXT NOT NULL,
    media TEXT,
    tags TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();
  await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_progress_created ON progress_posts(created_at DESC)').run();
  await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_progress_project ON progress_posts(project, created_at DESC)').run();
  await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_progress_agent ON progress_posts(agent_id, created_at DESC)').run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS progress_teams (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    project TEXT NOT NULL UNIQUE,
    handle TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    bio TEXT,
    avatar_url TEXT,
    created_by_agent_id TEXT REFERENCES api_keys(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS progress_likes (
    post_id TEXT NOT NULL REFERENCES progress_posts(id) ON DELETE CASCADE,
    boss_id TEXT NOT NULL REFERENCES bosses(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (post_id, boss_id)
  )`).run();
  await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_progress_likes_post ON progress_likes(post_id)').run();
}

beforeAll(async () => {
  await seedDatabase();
  await createProgressSchema();
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(OTHER_AGENT_ID, 'other-agent', await hashApiKey('progress-other-key')).run();
  await env.DB.prepare('INSERT OR IGNORE INTO bosses (id, name, role, token_hash) VALUES (?, ?, ?, ?)')
    .bind('progress-boss', 'Progress Boss', 'manager', await hashApiKey(BOSS_TOKEN)).run();
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind('progress-boss', getTestAgentId()).run();
  await env.DB.prepare('DELETE FROM progress_posts').run();
  await env.DB.prepare('DELETE FROM progress_teams').run();
  await env.DB.prepare('DELETE FROM progress_likes').run();
  await env.DB.prepare(
    "INSERT INTO progress_posts (id, agent_id, project, body, created_at) VALUES (?, ?, ?, ?, '2026-08-14 09:00:00'), (?, ?, ?, ?, '2026-08-14 08:00:00')"
  ).bind('progress-own', getTestAgentId(), 'hiboss', 'own post', 'progress-other', OTHER_AGENT_ID, 'other', 'other post').run();
});

describe('POST /api/progress', () => {
  it('creates a post with fallback project and normalized arrays', async () => {
    const upload = await SELF.fetch('https://test.local/api/attachments/upload', {
      method: 'POST',
      headers: { Authorization: authHeaders().Authorization, 'Content-Type': 'image/png', 'X-Filename': 'progress.png' },
      body: new Uint8Array([1, 2, 3]),
    });
    const attachment = await upload.json() as { url: string };
    const res = await SELF.fetch('https://test.local/api/progress', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({
        body: 'Shipped the feed',
        media: [{ url: attachment.url, kind: 'image', content_type: 'image/png', size: 3 }],
        tags: ['release'],
      }),
    });
    expect(res.status).toBe(201);
    const post = await res.json() as { project: string; agent_name: string; media: unknown[]; tags: string[]; created_at: string; team: { handle: string; display_name: string; avatar_url: string; registered: boolean }; like_count: number; liked: boolean };
    expect(post.project).toBe('test-agent');
    expect(post.agent_name).toBe('test-agent');
    expect(post.media).toHaveLength(1);
    expect(post.tags).toEqual(['release']);
    expect(post.created_at).toMatch(/T.*Z$/);
    expect(post.team).toMatchObject({ handle: 'test-agent', display_name: 'test-agent', registered: false });
    expect(post.team.avatar_url).toContain('/api/progress/teams/test-agent/avatar.png');
    expect(post.like_count).toBe(0);
    expect(post.liked).toBe(false);
  });

  it('rejects remote media URLs and oversized media lists', async () => {
    const remote = await SELF.fetch('https://test.local/api/progress', {
      method: 'POST', headers: authHeaders(),
      body: JSON.stringify({ body: 'bad media', media: [{ url: 'https://example.com/a.png', kind: 'image', content_type: 'image/png', size: 1 }] }),
    });
    expect(remote.status).toBe(400);
    const tooMany = await SELF.fetch('https://test.local/api/progress', {
      method: 'POST', headers: authHeaders(),
      body: JSON.stringify({ body: 'too many', media: [1, 2, 3, 4, 5] }),
    });
    expect(tooMany.status).toBe(400);
  });

  it('rejects missing and foreign attachment keys, including poster URLs', async () => {
    const missing = await SELF.fetch('https://test.local/api/progress', {
      method: 'POST', headers: authHeaders(),
      body: JSON.stringify({ body: 'missing media', media: [{ url: 'https://test.local/api/attachments/missing', kind: 'image', content_type: 'image/png', size: 1 }] }),
    });
    expect(missing.status).toBe(400);

    await env.ATTACHMENTS.put('owned-progress-video', new Uint8Array([1]), {
      httpMetadata: { contentType: 'video/mp4' },
      customMetadata: { agent_id: getTestAgentId() },
    });
    await env.ATTACHMENTS.put('foreign-progress-poster', new Uint8Array([1]), {
      httpMetadata: { contentType: 'image/jpeg' },
      customMetadata: { agent_id: OTHER_AGENT_ID },
    });
    const foreignPoster = await SELF.fetch('https://test.local/api/progress', {
      method: 'POST', headers: authHeaders(),
      body: JSON.stringify({
        body: 'foreign poster',
        media: [{ url: 'https://test.local/api/attachments/owned-progress-video', kind: 'video', content_type: 'video/mp4', size: 1, poster_url: 'https://test.local/api/attachments/foreign-progress-poster' }],
      }),
    });
    expect(foreignPoster.status).toBe(400);
  });

  it('does not insert a message or delivery row', async () => {
    const before = await env.DB.prepare('SELECT COUNT(*) AS count FROM messages').first<{ count: number }>();
    const queueBefore = await env.DB.prepare('SELECT COUNT(*) AS count FROM delivery_queue').first<{ count: number }>();
    const res = await SELF.fetch('https://test.local/api/progress', {
      method: 'POST', headers: authHeaders(), body: JSON.stringify({ body: 'no notification' }),
    });
    expect(res.status).toBe(201);
    const after = await env.DB.prepare('SELECT COUNT(*) AS count FROM messages').first<{ count: number }>();
    const queueAfter = await env.DB.prepare('SELECT COUNT(*) AS count FROM delivery_queue').first<{ count: number }>();
    expect(after?.count).toBe(before?.count);
    expect(queueAfter?.count).toBe(queueBefore?.count);
  });
});

describe('progress visibility and lifecycle', () => {
  it('limits agent feeds to the caller own posts', async () => {
    const res = await SELF.fetch('https://test.local/api/progress?limit=10', { headers: authHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { posts: { id: string }[] };
    expect(data.posts.map((post) => post.id)).toContain('progress-own');
    expect(data.posts.map((post) => post.id)).not.toContain('progress-other');
  });

  it('limits boss feeds to accessible agents and supports project summaries', async () => {
    const feed = await SELF.fetch('https://test.local/api/progress?agent_id=progress-other', { headers: bossHeaders() });
    expect(feed.status).toBe(200);
    const data = await feed.json() as { posts: { id: string }[] };
    expect(data.posts.map((post) => post.id)).toEqual([]);
    const projects = await SELF.fetch('https://test.local/api/progress/projects', { headers: bossHeaders() });
    const projectData = await projects.json() as { projects: { project: string; count: number; agent_id: string; last_post_at: string }[] };
    expect(projectData.projects).toContainEqual({ project: 'hiboss', count: 1, agent_id: getTestAgentId(), last_post_at: '2026-08-14T09:00:00Z' });
  });

  it('returns 404 for an out-of-scope post and deletes an own post', async () => {
    const hidden = await SELF.fetch('https://test.local/api/progress/progress-other', { headers: authHeaders() });
    expect(hidden.status).toBe(404);
    const deleted = await SELF.fetch('https://test.local/api/progress/progress-own', { method: 'DELETE', headers: authHeaders() });
    expect(deleted.status).toBe(204);
    const missing = await SELF.fetch('https://test.local/api/progress/progress-own', { headers: authHeaders() });
    expect(missing.status).toBe(404);
  });

  it('paginates every post sharing one timestamp with a composite cursor', async () => {
    await env.DB.prepare('DELETE FROM progress_posts').run();
    const ids = ['tie-a', 'tie-b', 'tie-c', 'tie-d', 'tie-e'];
    for (const id of ids) {
      await env.DB.prepare(
        "INSERT INTO progress_posts (id, agent_id, project, body, created_at) VALUES (?, ?, 'hiboss', ?, '2026-08-14 09:00:00')"
      ).bind(id, getTestAgentId(), id).run();
    }

    const seen: string[] = [];
    let cursor: { created_at: string; id: string } | null = null;
    for (;;) {
      const url = new URL('https://test.local/api/progress?limit=2');
      if (cursor) url.searchParams.set('before', JSON.stringify(cursor));
      const response = await SELF.fetch(url, { headers: authHeaders() });
      expect(response.status).toBe(200);
      const page = await response.json() as { posts: { id: string }[]; next_cursor: { created_at: string; id: string } | null };
      seen.push(...page.posts.map((post) => post.id));
      cursor = page.next_cursor;
      if (!cursor) break;
    }

    expect(seen).toHaveLength(ids.length);
    expect(new Set(seen).size).toBe(ids.length);
  });
});

describe('progress teams and likes', () => {
  it('serves deterministic valid PNG identicons that vary by handle', async () => {
    const first = await SELF.fetch('https://test.local/api/progress/teams/hiboss/avatar.png');
    const second = await SELF.fetch('https://test.local/api/progress/teams/hiboss/avatar.png');
    const different = await SELF.fetch('https://test.local/api/progress/teams/other/avatar.png');
    expect(first.status).toBe(200);
    expect(different.status).toBe(200);
    expect(first.headers.get('content-type')).toBe('image/png');
    expect(first.headers.get('cache-control')).toBe('public, max-age=31536000, immutable');
    const firstBytes = new Uint8Array(await first.arrayBuffer());
    const secondBytes = new Uint8Array(await second.arrayBuffer());
    const differentBytes = new Uint8Array(await different.arrayBuffer());
    expect(Array.from(firstBytes.slice(0, 8))).toEqual([137, 80, 78, 71, 13, 10, 26, 10]);
    expect(Array.from(firstBytes.slice(12, 16))).toEqual([73, 72, 68, 82]);
    expect(new DataView(firstBytes.buffer).getUint32(16)).toBe(64);
    expect(new DataView(firstBytes.buffer).getUint32(20)).toBe(64);
    expect(firstBytes).toEqual(secondBytes);
    expect(firstBytes).not.toEqual(differentBytes);
  });

  it('registers a team and includes fallback and registered identities in posts', async () => {
    await env.DB.prepare("INSERT OR IGNORE INTO progress_posts (id, agent_id, project, body) VALUES ('team-fallback', ?, 'unregistered project', 'fallback')")
      .bind(getTestAgentId()).run();
    const fallback = await SELF.fetch('https://test.local/api/progress/team-fallback', { headers: authHeaders() });
    const fallbackData = await fallback.json() as { team: { handle: string; display_name: string; avatar_url: string; registered: boolean } };
    expect(fallbackData.team).toMatchObject({ handle: 'unregistered-project', display_name: 'unregistered project', registered: false });
    expect(fallbackData.team.avatar_url).toContain('/api/progress/teams/unregistered-project/avatar.png');

    const registered = await SELF.fetch('https://test.local/api/progress/teams/hiboss', {
      method: 'PUT', headers: authHeaders(), body: JSON.stringify({ handle: 'hiboss', display_name: 'Hiboss Team', bio: 'shipping' }),
    });
    expect(registered.status).toBe(200);
    const team = await registered.json() as { handle: string; display_name: string; avatar_url: string; registered: boolean; bio: string };
    expect(team).toMatchObject({ handle: 'hiboss', display_name: 'Hiboss Team', registered: true, bio: 'shipping' });
    expect(team.avatar_url).toContain('/api/progress/teams/hiboss/avatar.png');

    const visibleTeams = await SELF.fetch('https://test.local/api/progress/teams', { headers: authHeaders() });
    const visibleTeamData = await visibleTeams.json() as { teams: { project: string; registered: boolean }[] };
    expect(visibleTeamData.teams).toEqual(expect.arrayContaining([
      expect.objectContaining({ project: 'hiboss', registered: true }),
      expect.objectContaining({ project: 'unregistered project', registered: false }),
    ]));

    await env.DB.prepare("INSERT OR IGNORE INTO progress_posts (id, agent_id, project, body) VALUES ('team-registered', ?, 'hiboss', 'registered')")
      .bind(getTestAgentId()).run();
    const post = await SELF.fetch('https://test.local/api/progress/team-registered', { headers: authHeaders() });
    const postData = await post.json() as { team: { handle: string; display_name: string; avatar_url: string; registered: boolean }; like_count: number; liked: boolean };
    expect(postData.team).toMatchObject({ handle: 'hiboss', display_name: 'Hiboss Team', registered: true });
    expect(postData.like_count).toBe(0);
    expect(postData.liked).toBe(false);
  });

  it('keeps like and unlike operations idempotent in both directions', async () => {
    await env.DB.prepare("INSERT OR IGNORE INTO progress_posts (id, agent_id, project, body) VALUES ('like-post', ?, 'hiboss', 'like me')")
      .bind(getTestAgentId()).run();
    const like = async (): Promise<Response> => SELF.fetch('https://test.local/api/progress/like-post/like', { method: 'POST', headers: bossHeaders() });
    const unlike = async (): Promise<Response> => SELF.fetch('https://test.local/api/progress/like-post/like', { method: 'DELETE', headers: bossHeaders() });

    const hiddenLike = await SELF.fetch('https://test.local/api/progress/progress-other/like', { method: 'POST', headers: bossHeaders() });
    expect(hiddenLike.status).toBe(404);
    const firstLike = await like();
    expect(firstLike.status).toBe(200);
    expect(await firstLike.json()).toEqual({ like_count: 1, liked: true });
    const secondLike = await like();
    expect(await secondLike.json()).toEqual({ like_count: 1, liked: true });
    const firstUnlike = await unlike();
    expect(await firstUnlike.json()).toEqual({ like_count: 0, liked: false });
    const secondUnlike = await unlike();
    expect(await secondUnlike.json()).toEqual({ like_count: 0, liked: false });
  });
});
