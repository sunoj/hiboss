// Notification client contracts cover CRUD, probes, credentials, and locale completeness.
// Depends on Vitest fetch mocks and the real typed console client.
import { afterEach, expect, it, vi } from 'vitest';
import { ApiError } from '$lib/api/types';
import { i18n, t } from '$lib/i18n';
import { NotificationsClient } from './client';
import type { DestinationId, ProviderId } from './types';
import { NAV_MODULES } from '$lib/nav';
const client = new NotificationsClient({ baseUrl: 'https://test', token: 'boss-token' });
afterEach(() => { vi.unstubAllGlobals(); i18n.setLocale('en', false); });
it('loads the current boss inventory, provider choices, and mode', async () => {
  const data = { destinations: [], providers: [], mode: 'shadow' };
  const fetch = vi.fn().mockResolvedValue(Response.json(data)); vi.stubGlobal('fetch', fetch);
  expect(await client.inventory()).toEqual(data);
  expect(fetch).toHaveBeenCalledWith('https://test/api/boss/destinations', expect.objectContaining({ method: 'GET', headers: expect.objectContaining({ Authorization: 'Bearer boss-token' }) }));
});
it.each(['patch', 'remove', 'test'] as const)('encodes destination IDs for %s', async action => {
  const fetch = vi.fn().mockResolvedValue(Response.json({ ok: true })); vi.stubGlobal('fetch', fetch);
  const id = 'chat/1' as DestinationId;
  if (action === 'patch') await client.patch(id, { enabled: false, min_priority: 'high', honours_quiet_hours: false });
  else await client[action](id);
  expect(fetch.mock.calls[0][0]).toBe(`https://test/api/boss/destinations/chat%2F1${action === 'test' ? '/test' : ''}`);
  expect(fetch.mock.calls[0][1].method).toBe(action === 'patch' ? 'PATCH' : action === 'remove' ? 'DELETE' : 'POST');
  if (action === 'patch') expect(JSON.parse(fetch.mock.calls[0][1].body)).toEqual({ enabled: false, min_priority: 'high', honours_quiet_hours: false });
});
it.each(['telegram_chat', 'discord_channel'] as const)('creates a %s using an existing provider', async kind => {
  const fetch = vi.fn().mockResolvedValue(Response.json({ destination: { id: 'new' } })); vi.stubGlobal('fetch', fetch);
  const input = { kind, provider_id: 'p' as ProviderId, label: 'Chat', target: kind === 'telegram_chat' ? { chat_id: '-123' } : { channel_id: '123' } };
  await client.create(input);
  expect(fetch.mock.calls[0][0]).toBe('https://test/api/boss/destinations');
  expect(JSON.parse(fetch.mock.calls[0][1].body)).toEqual(input);
});
it('sends provider credentials only in the authenticated POST body', async () => {
  const fetch = vi.fn().mockResolvedValue(Response.json({ provider: { id: 'p' } })); vi.stubGlobal('fetch', fetch);
  await client.createProvider({ provider: 'telegram', label: 'Bot', credentials: { bot_token: 'secret' } });
  expect(fetch.mock.calls[0][0]).toBe('https://test/api/boss/providers');
  expect(JSON.parse(fetch.mock.calls[0][1].body).credentials).toEqual({ bot_token: 'secret' });
});
it.each([403, 404, 409, 502])('propagates HTTP %s for visible error handling', async status => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('failed', { status })));
  await expect(client.test('id' as DestinationId)).rejects.toEqual(new ApiError(status, 'failed'));
});
it.each(['en', 'zh-CN', 'ja', 'ko'] as const)('translates notification controls in %s', locale => {
  i18n.setLocale(locale, false);
  for (const key of ['notifications.title', 'notifications.testHint', 'notifications.priority', 'notifications.credentials'] as const) expect(t(key)).not.toBe(key);
  expect(t('notifications.routes', { count: 2 })).toContain('2');
});
it('lists Notifications in navigation and leaves Channels unlisted', () => {
  expect(NAV_MODULES.some(row => row.href === '/notifications')).toBe(true);
  expect(NAV_MODULES.some(row => row.href === '/channels')).toBe(false);
});
