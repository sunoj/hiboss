// Notification client contracts cover client inventory, updates, probes, and locale completeness.
// Depends on Vitest fetch mocks and the real typed console client.
import { afterEach, expect, it, vi } from 'vitest';
import { ApiError } from '$lib/api/types';
import { i18n, t } from '$lib/i18n';
import { NotificationsClient } from './client';
import type { DestinationId } from './types';
import { NAV_MODULES } from '$lib/nav';
const client = new NotificationsClient({ baseUrl: 'https://test', token: 'boss-token' });
afterEach(() => { vi.unstubAllGlobals(); i18n.setLocale('en', false); });
const inventoryCases = [
  { kind: 'apns', visible: true },
  { kind: 'native_live', visible: true },
  { kind: 'telegram_chat', visible: false },
  { kind: 'discord_channel', visible: false },
  { kind: 'future_kind', visible: false },
] as const;

for (const mode of ['off', 'shadow', 'on'] as const) {
  it.each(inventoryCases)(`filters $kind in ${mode} mode according to HiBoss client support`, async ({ kind, visible }) => {
    const row = { kind, id: 'destination-1' };
    const fetch = vi.fn().mockResolvedValue(Response.json({ destinations: [row], providers: [], mode }));
    vi.stubGlobal('fetch', fetch);
    expect(await client.inventory()).toEqual({ destinations: visible ? [row] : [], mode });
    expect(fetch).toHaveBeenCalledWith('https://test/api/boss/destinations', expect.objectContaining({
      method: 'GET', headers: expect.objectContaining({ Authorization: 'Bearer boss-token' })
    }));
  });
}

it.each(['patch', 'test'] as const)('encodes destination IDs for %s', async action => {
  const fetch = vi.fn().mockResolvedValue(Response.json({ ok: true }));
  vi.stubGlobal('fetch', fetch);
  const id = 'device/1' as DestinationId;
  const patch = { enabled: false, min_priority: 'high', honours_quiet_hours: false } as const;
  if (action === 'patch') await client.patch(id, patch);
  else await client.test(id);
  const [url, request] = fetch.mock.calls[0];
  expect(url).toBe(`https://test/api/boss/destinations/device%2F1${action === 'test' ? '/test' : ''}`);
  expect(request.method).toBe(action === 'patch' ? 'PATCH' : 'POST');
  if (action === 'patch') expect(JSON.parse(request.body)).toEqual(patch);
});

it.each([403, 404, 409, 502])('propagates HTTP %s for visible error handling', async status => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('failed', { status })));
  await expect(client.test('id' as DestinationId)).rejects.toEqual(new ApiError(status, 'failed'));
});
it.each(['en', 'zh-CN', 'ja', 'ko'] as const)('translates notification controls in %s', locale => {
  i18n.setLocale(locale, false);
  for (const key of ['notifications.title', 'notifications.testHint', 'notifications.priority', 'notifications.native_live', 'notifications.apns'] as const) expect(t(key)).not.toBe(key);
  expect(t('notifications.routes', { count: 2 })).toContain('2');
});
it('lists Delivery in navigation and keeps legacy Notifications and Channels unlisted', () => {
  expect(NAV_MODULES.some(row => row.href === '/delivery')).toBe(true);
  expect(NAV_MODULES.some(row => row.href === '/notifications')).toBe(false);
  expect(NAV_MODULES.some(row => row.href === '/channels')).toBe(false);
  expect(NAV_MODULES.some(row => row.href === '/routing')).toBe(false);
});
