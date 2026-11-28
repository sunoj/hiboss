// Covers read compatibility with existing server records after channel removal.
// Uses fetch stubs for the authenticated console API.
import { afterEach, expect, it, vi } from 'vitest';
import { BossApiClient } from './client';

const client = new BossApiClient({ baseUrl: 'https://test.local', token: 'boss-token' });

afterEach(() => vi.unstubAllGlobals());

const healthCases = [
	{ label: 'built-in API', rows: ['api'], expected: ['api'] },
	{ label: 'legacy channels alongside API', rows: ['discord', 'api', 'telegram'], expected: ['api'] },
	{ label: 'Discord only', rows: ['discord'], expected: [] },
	{ label: 'Telegram only', rows: ['telegram'], expected: [] },
	{ label: 'empty inventory', rows: [], expected: [] }
];

for (const endpoint of ['overview', 'system'] as const) {
	it.each(healthCases)(`shows only built-in delivery health in ${endpoint} with $label`, async ({ rows, expected }) => {
		const channels = rows.map((channel) => ({ channel, configured: true }));
		vi.stubGlobal('fetch', vi.fn().mockResolvedValue(Response.json({ channels })));
		expect((await client[endpoint]()).channels.map(({ channel }) => channel)).toEqual(expected);
	});
}

it.each(['discord', 'telegram'] as const)('preserves the historical %s source in messages', async (channel) => {
	const message = { id: 'historical', body: 'Stored message', channel };
	const read = vi.fn().mockResolvedValueOnce(Response.json(message))
		.mockResolvedValueOnce(Response.json({ messages: [message], total: 1 }));
	vi.stubGlobal('fetch', read);
	expect(await client.message(message.id)).toMatchObject(message);
	expect((await client.messages()).messages).toEqual([expect.objectContaining(message)]);
});
