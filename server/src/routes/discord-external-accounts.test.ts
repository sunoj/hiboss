// Signed Discord interactions recognize the new external account before legacy IDs.
// Depends on the real Worker router, Ed25519 signatures, and isolated D1 fixtures.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import app from '../index';
import { seedDatabase } from '../test-helpers';
beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare("INSERT INTO bosses (id, name, role, discord_user_id) VALUES ('legacy', 'Legacy', 'viewer', '123'), ('current', 'Current', 'admin', NULL)").run();
  await env.DB.prepare("INSERT INTO boss_external_accounts (boss_id, provider, provider_user_id) VALUES ('current', 'discord', '123')").run();
  await env.DB.prepare("INSERT INTO channel_configs (agent_id, channel, config) VALUES ('test-agent-id', 'discord', '{\"channel_id\":\"10\",\"bot_token\":\"fake\"}')").run();
});
function hex(buffer: ArrayBuffer): string { return Array.from(new Uint8Array(buffer), byte => byte.toString(16).padStart(2, '0')).join(''); }
it('authorizes a signed slash command using the account owner instead of the legacy viewer', async () => {
  const key = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const publicKey = hex(await crypto.subtle.exportKey('raw', key.publicKey));
  const timestamp = String(Math.floor(Date.now() / 1000));
  const body = JSON.stringify({ type: 2, channel_id: '10', member: { user: { id: '123' } },
    data: { name: 'msg', options: [{ name: 'message', value: 'identity precedence' }] } });
  const signature = hex(await crypto.subtle.sign('Ed25519', key.privateKey, new TextEncoder().encode(timestamp + body)));
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request('https://test/api/webhooks/discord-interactions', {
    method: 'POST', headers: { 'X-Signature-Timestamp': timestamp, 'X-Signature-Ed25519': signature }, body,
  }), { ...env, DISCORD_PUBLIC_KEY: publicKey }, ctx);
  await waitOnExecutionContext(ctx);
  expect(response.status).toBe(200);
  expect(await response.json()).toMatchObject({ data: { content: 'Message sent to agent.' } });
  const row = await env.DB.prepare("SELECT metadata FROM messages WHERE body = 'identity precedence'").first<{ metadata: string }>();
  expect(row?.metadata).toContain('current');
});
