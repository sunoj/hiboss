// Tests the Channels page's update API contract and translated feedback.
// Depends on BossApiClient, i18n, and Vitest fetch mocks.
import { afterEach, expect, it, vi } from 'vitest';
import { BossApiClient } from '$lib/api/client';
import { ApiError } from '$lib/api/types';
import { i18n, t } from '$lib/i18n';

afterEach(() => {
	vi.unstubAllGlobals();
	i18n.setLocale('en', false);
});

it('sends a boolean PATCH with boss auth and preserves the server warning', async () => {
	const row = { id: 'channel/1', enabled: 0, warning: 'agent has no enabled channel; hiboss send will fail' };
	const fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify(row)));
	vi.stubGlobal('fetch', fetch);
	const client = new BossApiClient({ baseUrl: 'https://test.local', token: 'boss-token' });
	expect(await client.updateChannel('channel/1', false)).toEqual(row);
	expect(fetch).toHaveBeenCalledWith('https://test.local/api/boss/channels/channel%2F1', expect.objectContaining({
		method: 'PATCH', body: '{"enabled":false}',
		headers: expect.objectContaining({ Authorization: 'Bearer boss-token', 'Content-Type': 'application/json' })
	}));
});

it('propagates rejected toggles for inline error handling', async () => {
	vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('viewer cannot write', { status: 403 })));
	const client = new BossApiClient({ token: 'viewer-token' });
	await expect(client.updateChannel('channel', true)).rejects.toEqual(new ApiError(403, 'viewer cannot write'));
});

it('translates toggle labels and feedback in English and Chinese', () => {
	expect(t('channel.toggle', { channel: 'email', agent: 'Ops' })).toBe('email notifications for Ops');
	expect(t('channel.noEnabledWarning')).toBe('agent has no enabled channel; hiboss send will fail');
	i18n.setLocale('zh-CN', false);
	expect(t('channel.toggle', { channel: 'email', agent: 'Ops' })).toBe('Ops 的 email 通知');
	expect(t('channel.updateFailed')).toBe('无法更新渠道');
	expect(t('channel.noEnabledWarning')).toBe('智能体没有已启用的渠道；hiboss send 将失败');
});
