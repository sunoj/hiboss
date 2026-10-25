// Resolution fan-out tests: direct background push, relay body, audience, quiet hours, pruning,
// Live Activity end payloads against the shared fixture and audience, the scheduled token purge,
// and the scheduled run's capped, concurrent resolution sweep.
// Uses real D1 and WebCrypto with stubbed outbound fetch; tokens are fake fixtures.
import { env } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import fixtureText from '../../../docs/fixtures/live-activity-end-state.json?raw';
import { seedDatabase } from '../test-helpers';
import { endContentState, purgeLiveActivityTokens } from './live-activity';
import { handleScheduled } from '../scheduled';
import { announceResolution, SWEEP_RESOLUTION_LIMIT } from './resolution';
import {
  apnsEnv, captureFetch, insertAsk, liveTokenId, openResolved, relayHandle, relayResolutions, seedAudience,
} from './resolution-test-support';
import type { Env, MessageRow } from '../types';

const fixture = JSON.parse(fixtureText) as Record<'replied' | 'auto_default' | 'expired', unknown>;
const QUIET = JSON.stringify({ quiet_hours: { enabled: true, start: '00:00', end: '23:59', timezone: 'UTC' },
  push: { critical: { deliver: false }, high: { deliver: false }, normal: { deliver: false }, low: { deliver: false } },
  private_push: true });
let direct: Env;

beforeAll(async () => {
  await seedDatabase();
  direct = await apnsEnv();
});
afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

async function ask(id: string, agentId: string, fields: Record<string, unknown> = {}): Promise<MessageRow> {
  await insertAsk(id, agentId, fields);
  return (await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(id).first<MessageRow>())!;
}

describe('direct mode', () => {
  it('sends a silent background push to every device of the ask audience despite quiet hours', async () => {
    const { agentId } = await seedAudience('direct-quiet', { token: 'aa01' }, QUIET);
    await env.DB.prepare(`INSERT INTO bosses (id, name, role) VALUES ('direct-quiet-outsider', 'Outsider', 'manager')`).run();
    await env.DB.prepare(`INSERT INTO boss_devices (boss_id, device_token, bundle_id, environment, token_id)
      VALUES ('direct-quiet-outsider', 'ff01', 'ai.hiboss.app', 'sandbox', ?)`).bind(await liveTokenId('direct-quiet-outsider')).run();
    const captured = captureFetch();
    await announceResolution(direct, await ask('direct-quiet-ask', agentId), 'replied');
    const sent = captured.filter((r) => r.url.includes('/3/device/'));
    expect(sent.map((r) => r.url)).toEqual(['https://api.sandbox.push.apple.com/3/device/aa01']);
    expect(sent[0].headers).toMatchObject({ 'apns-push-type': 'background', 'apns-priority': '5',
      'apns-topic': 'ai.hiboss.app' });
    expect(sent[0].headers['apns-collapse-id']).toBeUndefined();
    expect(sent[0].body).toEqual({ aps: { 'content-available': 1 },
      hiboss: { resolved: { id: 'direct-quiet-ask', status: 'replied' } } });
  });

  it('prunes a device APNs answers 410 for, and swallows transport failures', async () => {
    const { agentId } = await seedAudience('direct-prune', { token: 'aa02' });
    captureFetch(410);
    await announceResolution(direct, await ask('direct-prune-ask', agentId), 'expired');
    expect(await env.DB.prepare("SELECT 1 FROM boss_devices WHERE device_token = 'aa02'").first()).toBeNull();
    await seedAudience('direct-throw', { token: 'aa03' });
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('network down'); }));
    await expect(announceResolution(direct, await ask('direct-throw-ask', 'direct-throw-agent'), 'expired'))
      .resolves.toBeUndefined();
  });

  it('sends nothing for a message that is not an agent ask', async () => {
    const { agentId } = await seedAudience('direct-plain', { token: 'aa04' });
    const captured = captureFetch();
    await announceResolution(direct, await ask('direct-plain-msg', agentId, { metadata: null }), 'replied');
    expect(captured).toHaveLength(0);
  });
});

describe('relay mode', () => {
  it('posts kind resolved at priority 5 with only id and status encrypted', async () => {
    const { agentId } = await seedAudience('relay-res', { token: '', relay: true }, QUIET);
    const captured = captureFetch(202);
    await announceResolution(env, await ask('relay-res-ask', agentId, { mode: 'blocking', metadata: null }), 'expired');
    const sent = captured.filter((r) => r.url === 'https://push.hiboss.org/v1/push');
    expect(sent).toHaveLength(1);
    expect(Object.keys(sent[0].body).sort()).toEqual(['ciphertext', 'handle', 'kind', 'priority']);
    expect(sent[0].body).toMatchObject({ handle: relayHandle('relay-res'), kind: 'resolved', priority: 5 });
    expect(await relayResolutions(captured)).toEqual([{ id: 'relay-res-ask', status: 'expired' }]);
  });
});

describe('Live Activity end', () => {
  it('builds the shared fixture states', () => {
    expect(endContentState('normal', { kind: 'answeredElsewhere', answer: 'Ship' })).toEqual(fixture.replied);
    expect(endContentState('normal', { kind: 'autoSelected', answer: 'Hold' })).toEqual(fixture.auto_default);
    expect(endContentState('normal', null)).toEqual(fixture.expired);
  });

  it.each([
    ['replied', 'replied', {}, 'Ship', 'bb01'],
    ['auto_default', 'replied', { auto_default: true }, 'Hold', 'bb02'],
    ['expired', 'expired', null, null, 'bb03'],
  ] as const)('ends every activity of a %s ask with the fixture state, then deletes the rows',
    async (name, status, replyMeta, answer, token) => {
      const prefix = `la-${name.replace('_', '-')}`;
      const { agentId } = await seedAudience(prefix, { token });
      const message = await ask(`${prefix}-ask`, agentId);
      if (replyMeta) {
        await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, body, status, reply_to, metadata)
          VALUES (?, ?, 'boss_to_agent', 'async', ?, 'sent', ?, ?)`)
          .bind(`${prefix}-reply`, agentId, answer, message.id, JSON.stringify(replyMeta)).run();
      }
      await env.DB.prepare(`INSERT INTO live_activity_tokens (device_id, message_id, activity_token, environment)
        SELECT id, ?, 'abcd01', 'production' FROM boss_devices WHERE boss_id = ?`).bind(message.id, `${prefix}-boss`).run();
      const captured = captureFetch();
      await announceResolution(direct, message, status);
      const ends = captured.filter((r) => r.headers['apns-push-type'] === 'liveactivity');
      expect(ends.map((r) => r.url)).toEqual(['https://api.push.apple.com/3/device/abcd01']);
      expect(ends[0].headers).toMatchObject({ 'apns-priority': '10',
        'apns-topic': 'ai.hiboss.app.push-type.liveactivity' });
      const aps = ends[0].body.aps as Record<string, unknown>;
      expect(aps.event).toBe('end');
      expect(aps['dismissal-date']).toBe(aps.timestamp);
      expect(Math.abs(Number(aps.timestamp) - Date.now() / 1000)).toBeLessThan(60);
      expect(aps['content-state']).toEqual(fixture[name]);
      expect(await env.DB.prepare('SELECT 1 FROM live_activity_tokens WHERE message_id = ?')
        .bind(message.id).first()).toBeNull();
    });

  it('ends no activity on a device whose boss lost access to the agent, and drops its rows', async () => {
    const { agentId, bossId } = await seedAudience('la-revoked', { token: 'bb04' });
    const message = await ask('la-revoked-ask', agentId);
    await env.DB.prepare(`INSERT INTO live_activity_tokens (device_id, message_id, activity_token, environment)
      SELECT id, ?, 'abcd04', 'production' FROM boss_devices WHERE boss_id = ?`).bind(message.id, bossId).run();
    await env.DB.prepare('DELETE FROM boss_agent_access WHERE boss_id = ?').bind(bossId).run();
    const captured = captureFetch();
    await announceResolution(direct, message, 'replied');
    expect(captured.filter((r) => r.headers['apns-push-type'] === 'liveactivity')).toEqual([]);
    expect(await env.DB.prepare('SELECT 1 FROM live_activity_tokens WHERE message_id = ?')
      .bind(message.id).first()).toBeNull();
  });

  it('purges rows older than 48 hours and keeps fresh ones', async () => {
    const { agentId, bossId } = await seedAudience('la-purge', { token: 'cc01' });
    await ask('la-purge-old', agentId);
    await ask('la-purge-new', agentId);
    await env.DB.prepare(`INSERT INTO live_activity_tokens (device_id, message_id, activity_token, environment, updated_at)
      SELECT id, 'la-purge-old', 'ee01', 'sandbox', datetime('now', '-49 hours') FROM boss_devices WHERE boss_id = ?`)
      .bind(bossId).run();
    await env.DB.prepare(`INSERT INTO live_activity_tokens (device_id, message_id, activity_token, environment, updated_at)
      SELECT id, 'la-purge-new', 'ee02', 'sandbox', datetime('now', '-47 hours') FROM boss_devices WHERE boss_id = ?`)
      .bind(bossId).run();
    await purgeLiveActivityTokens(env);
    const rows = await env.DB.prepare("SELECT message_id FROM live_activity_tokens WHERE message_id LIKE 'la-purge-%'")
      .all<{ message_id: string }>();
    expect(rows.results.map((r) => r.message_id)).toEqual(['la-purge-new']);
  });
});

describe('scheduled sweep', () => {
  const two = (i: number) => String(i).padStart(2, '0');

  it('sends the newest resolutions up to the limit, several asks at a time', async () => {
    // Minute 2 of the hour, so the run also sweeps stale asks: 30 deadline + 25 stale transitions.
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-10-23T12:02:00Z'));
    const { agentId } = await seedAudience('sweep-cap', { token: '', relay: true });
    for (let i = 0; i < 30; i += 1) {
      await insertAsk(`sweep-due-${two(i)}`, agentId,
        { expires_at: '2026-10-23T12:00:00Z', created_at: `2026-10-01 10:${two(i)}:00` });
    }
    for (let i = 0; i < 25; i += 1) {
      await insertAsk(`sweep-stale-${two(i)}`, agentId, { created_at: `2020-01-01 00:${two(i)}:00` });
    }
    let inFlight = 0;
    let peak = 0;
    const sent: Promise<Record<string, unknown>>[] = [];
    vi.stubGlobal('fetch', vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      sent.push(openResolved(String((JSON.parse(String(init?.body)) as Record<string, unknown>).ciphertext)));
      inFlight += 1;
      peak = Math.max(peak, inFlight);
      await new Promise((resolve) => setTimeout(resolve, 5));
      inFlight -= 1;
      return new Response('{}', { status: 202 });
    }));
    await handleScheduled(env);
    vi.useRealTimers();
    const ids = (await Promise.all(sent)).map((r) => String(r.id)).filter((id) => id.startsWith('sweep-'));
    expect(SWEEP_RESOLUTION_LIMIT).toBe(50);
    expect(ids.sort()).toEqual([...Array.from({ length: 30 }, (_, i) => `sweep-due-${two(i)}`),
      ...Array.from({ length: 20 }, (_, i) => `sweep-stale-${two(i + 5)}`)]);
    expect(peak).toBeGreaterThan(1);
    expect(peak).toBeLessThanOrEqual(6);
    const open = await env.DB.prepare("SELECT COUNT(*) AS n FROM messages WHERE id LIKE 'sweep-%' AND status = 'sent'")
      .first<{ n: number }>();
    expect(open?.n).toBe(0);
  });
});
