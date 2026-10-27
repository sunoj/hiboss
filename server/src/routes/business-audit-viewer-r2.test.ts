// Round-two viewer regressions: a viewer is read-only on every writer, channel buttons included.
// Covers Telegram/Discord option callbacks, channel reactions, receipt PATCH, progress delete,
// client minting, and the rule that a channel callback never stores free text.

import { testRequest } from '../test-request';
import { env, SELF } from 'cloudflare:test';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { persistDiscordReaction } from '../discord-gateway-reactions';
import { seedBossToken, seedDatabase } from '../test-helpers';

const base = 'https://test.local';
const secret = 'viewer-r2-secret';
const viewerToken = 'viewer-r2-viewer-token';
const managerToken = 'viewer-r2-manager-token';
const ids = { tgViewer: 'viewer-r2-tg-v', tgManager: 'viewer-r2-tg-m', dcViewer: 'viewer-r2-dc-v', dcManager: 'viewer-r2-dc-m' };
const fresh = () => crypto.randomUUID().replaceAll('-', '');
const agent = fresh();
const chat = fresh();
const discordChannel = fresh();
let signingKey: CryptoKey;

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)').bind(agent, 'viewer-r2-agent', fresh()).run();
  await env.DB.prepare("INSERT INTO channel_configs (id, agent_id, channel, config) VALUES (?, ?, 'telegram', ?), (?, ?, 'discord', ?)")
    .bind(fresh(), agent, JSON.stringify({ chat_id: chat, bot_token: 'synthetic' }),
      fresh(), agent, JSON.stringify({ channel_id: discordChannel, bot_token: 'synthetic' })).run();
  for (const [role, token, tg, dc] of [['viewer', viewerToken, ids.tgViewer, ids.dcViewer],
    ['manager', managerToken, ids.tgManager, ids.dcManager]] as const) {
    const boss = await seedBossToken(`Viewer R2 ${role}`, role, token, fresh());
    await env.DB.prepare('UPDATE bosses SET telegram_user_id = ?, discord_user_id = ? WHERE id = ?').bind(tg, dc, boss).run();
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(boss, agent).run();
  }
  env.TELEGRAM_WEBHOOK_SECRET = secret;
  const pair = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']) as CryptoKeyPair;
  signingKey = pair.privateKey;
  env.DISCORD_PUBLIC_KEY = hex(await crypto.subtle.exportKey('raw', pair.publicKey) as ArrayBuffer);
});

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn(async () => new Response('{"ok":true,"result":{}}', { status: 200 })));
});

function hex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer)).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function message(fields: { direction?: string; mode?: string; channel?: string; metadata?: Record<string, unknown> } = {}): Promise<string> {
  const id = fresh();
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, metadata, expires_at)
    VALUES (?, ?, ?, ?, ?, 'Choose', 'delivered', ?, ?)`)
    .bind(id, agent, fields.direction ?? 'agent_to_boss', fields.mode ?? 'blocking', fields.channel ?? 'telegram',
      JSON.stringify(fields.metadata ?? { options: ['approve', 'reject'] }), new Date(Date.now() + 60_000).toISOString()).run();
  return id;
}

async function state(id: string): Promise<{ status: string; answers: number; reactions: unknown }> {
  const row = await env.DB.prepare('SELECT status, metadata FROM messages WHERE id = ?').bind(id).first<{ status: string; metadata: string }>();
  const count = await env.DB.prepare('SELECT COUNT(*) AS n FROM messages WHERE reply_to = ?').bind(id).first<{ n: number }>();
  return { status: row?.status ?? 'missing', answers: count?.n ?? 0, reactions: JSON.parse(row?.metadata ?? '{}').reactions };
}

function telegram(update: Record<string, unknown>): Promise<Response> {
  return testRequest('POST', `${base}/api/webhooks/telegram`,
    { 'Content-Type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': secret }, update);
}

function tap(parent: string, choice: string, from: string): Promise<Response> {
  return telegram({ callback_query: { id: fresh(), data: `${parent.slice(0, 12)}:${choice}`, from: { id: from },
    message: { message_id: 1, chat: { id: chat }, text: 'Choose' } } });
}

async function press(parent: string, choice: string, user: string): Promise<{ status: number; content: string | undefined }> {
  const body = JSON.stringify({ type: 3, channel_id: discordChannel, member: { user: { id: user } },
    data: { custom_id: `${parent.slice(0, 12)}:${choice}` }, message: { content: 'Choose' } });
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = hex(await crypto.subtle.sign('Ed25519', signingKey, new TextEncoder().encode(timestamp + body)));
  const response = await SELF.fetch(`${base}/api/webhooks/discord-interactions`, { method: 'POST', body,
    headers: { 'Content-Type': 'application/json', 'X-Signature-Timestamp': timestamp, 'X-Signature-Ed25519': signature } });
  const text = await response.text();
  try {
    return { status: response.status, content: (JSON.parse(text) as { data?: { content?: string } }).data?.content };
  } catch {
    return { status: response.status, content: text };
  }
}

function boss(path: string, token: string, method: string, body?: unknown): Promise<Response> {
  return SELF.fetch(`${base}${path}`, { method, body: body === undefined ? undefined : JSON.stringify(body),
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' } });
}

describe('DL1/MA2: channel option buttons', () => {
  it('rejects a viewer Telegram button press on an option ask', async () => {
    const control = await message();
    expect((await tap(control, 'approve', ids.tgManager)).status).toBe(201);
    expect(await state(control)).toMatchObject({ status: 'replied', answers: 1 });
    const target = await message();
    const response = await tap(target, 'approve', ids.tgViewer);
    expect(response.status).toBe(403);
    expect(await response.text()).toBe('viewer cannot answer');
    expect(await state(target)).toMatchObject({ status: 'delivered', answers: 0 });
  });

  it('rejects a viewer Discord button press on an option ask', async () => {
    const control = await message({ channel: 'discord' });
    expect((await press(control, 'approve', ids.dcManager)).content).toContain('Selected: approve');
    expect(await state(control)).toMatchObject({ status: 'replied', answers: 1 });
    const target = await message({ channel: 'discord' });
    expect((await press(target, 'approve', ids.dcViewer)).content).toBe('Viewer cannot answer');
    expect(await state(target)).toMatchObject({ status: 'delivered', answers: 0 });
  });

  it.each([
    ['a blocking text ask', { metadata: {} }, 400],
    ['an async agent message', { mode: 'async', metadata: {} }, 400],
    ['a boss_to_agent row', { direction: 'boss_to_agent', mode: 'async', metadata: {} }, 404],
  ])('never stores Telegram callback free text on %s', async (_label, fields, rejected) => {
    const target = await message(fields);
    expect((await tap(target, 'rm -rf build', ids.tgManager)).status).toBe(rejected);
    expect(await state(target)).toMatchObject({ status: 'delivered', answers: 0 });
  });

  it('never stores Discord custom_id free text on a blocking text ask', async () => {
    const target = await message({ channel: 'discord', metadata: {} });
    expect((await press(target, 'rm -rf build', ids.dcManager)).status).toBe(400);
    expect(await state(target)).toMatchObject({ status: 'delivered', answers: 0 });
  });
});

describe('DL6/MA8: viewer reactions and receipts', () => {
  async function tgMessage(telegramId: number): Promise<string> {
    return message({ mode: 'async', metadata: { telegram_message_id: telegramId, telegram_chat_id: chat } });
  }
  const react = (telegramId: number, user: string) => telegram({ message_reaction: { chat: { id: chat },
    message_id: telegramId, user: { id: user }, new_reaction: [{ type: 'emoji', emoji: '👍' }] } });

  it('rejects a viewer Telegram reaction', async () => {
    const control = await tgMessage(9101);
    expect((await react(9101, ids.tgManager)).status).toBe(200);
    expect((await state(control)).reactions).toHaveLength(1);
    const target = await tgMessage(9102);
    expect((await react(9102, ids.tgViewer)).status).toBe(403);
    expect((await state(target)).reactions).toBeUndefined();
  });

  it('rejects a viewer Discord gateway reaction', async () => {
    const reaction = (user: string, discordId: string) => ({ user_id: user, channel_id: discordChannel,
      message_id: discordId, emoji: { id: null, name: '👍' } });
    const control = await message({ channel: 'discord', mode: 'async', metadata: { discord_message_id: 'viewer-r2-d1' } });
    expect(await persistDiscordReaction(env, agent, reaction(ids.dcManager, 'viewer-r2-d1'), 'add')).toBe(true);
    expect((await state(control)).reactions).toHaveLength(1);
    const target = await message({ channel: 'discord', mode: 'async', metadata: { discord_message_id: 'viewer-r2-d2' } });
    expect(await persistDiscordReaction(env, agent, reaction(ids.dcViewer, 'viewer-r2-d2'), 'add')).toBe(false);
    expect((await state(target)).reactions).toBeUndefined();
  });

  it('rejects a viewer receipt PATCH on the boss API', async () => {
    const control = await message({ channel: 'api' });
    expect((await boss(`/api/boss/messages/${control}`, managerToken, 'PATCH', { status: 'read' })).status).toBe(200);
    const target = await message({ channel: 'api' });
    expect((await boss(`/api/boss/messages/${target}`, viewerToken, 'PATCH', { status: 'read' })).status).toBe(403);
    expect((await state(target)).status).toBe('delivered');
  });
});

describe('SP1/BG9: viewer progress delete and client minting', () => {
  it('rejects a viewer deleting a progress post', async () => {
    await env.DB.prepare("INSERT OR IGNORE INTO projects (id, slug, display_name) VALUES ('viewer-r2', 'viewer-r2', 'viewer-r2')").run();
    const [control, target] = [fresh(), fresh()];
    await env.DB.prepare("INSERT INTO progress_posts (id, agent_id, project_id, body) VALUES (?, ?, 'viewer-r2', 'a'), (?, ?, 'viewer-r2', 'b')")
      .bind(control, agent, target, agent).run();
    expect((await boss(`/api/progress/${control}`, managerToken, 'DELETE')).status).toBe(204);
    expect((await boss(`/api/progress/${target}`, viewerToken, 'DELETE')).status).toBe(403);
    expect(await env.DB.prepare('SELECT id FROM progress_posts WHERE id = ?').bind(target).first()).not.toBeNull();
  });

  it('rejects a viewer minting a new client and token', async () => {
    const body = { kind: 'web', label: 'Viewer R2' };
    expect((await boss('/api/boss/clients', managerToken, 'POST', body)).status).toBe(201);
    const before = await env.DB.prepare('SELECT COUNT(*) AS n FROM boss_clients').first<{ n: number }>();
    expect((await boss('/api/boss/clients', viewerToken, 'POST', body)).status).toBe(403);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM boss_clients').first<{ n: number }>()).toEqual(before);
  });
});
