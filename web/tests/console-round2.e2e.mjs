// Remote browser coverage for optional agent capabilities and live transcripts.
// Run with node --test against the console preview.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mockApi } from './console-fixture.mjs';

if (!process.env.HIBOSS_REMOTE_E2E) throw new Error('Run on an authorized remote build box');
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const baseURL = process.env.WEB_URL || 'http://127.0.0.1:4178';
let browser;
before(async () => { browser = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM }); });
after(async () => { await browser?.close(); });

async function setup(role = 'admin', capabilities = true) {
	const page = await browser.newPage({ viewport: { width: 375, height: 812 } });
	const patches = [];
	await mockApi(page, { capabilities, patches });
	await page.addInitScript(({ baseURL, role }) => {
		localStorage.setItem('hiboss.locale', 'en');
		localStorage.setItem('hiboss.web.connection', JSON.stringify({
			baseUrl: baseURL, token: 'fixture', boss: { id: 'boss', name: 'Robin', role }
		}));
	}, { baseURL, role });
	return { page, patches };
}

test('admin can patch advertised capability and see persisted sending defaults', async () => {
	const { page, patches } = await setup();
	try {
		await page.goto(baseURL + '/agents');
		await page.getByRole('link', { name: /Builder One.*Admin capability/ }).click();
		const toggle = page.getByRole('switch', { name: 'Admin capability' });
		await toggle.waitFor();
		assert.equal(await toggle.isChecked(), true);
		assert.equal(await page.getByLabel('Default priority').inputValue(), 'high');
		assert.equal(await page.getByLabel(/Rate limit/).inputValue(), '12');
		await toggle.click();
		await page.waitForFunction(() => {
			const input = document.querySelector('input[role="switch"]');
			return input && !input.checked;
		});
		assert.equal(await toggle.isChecked(), false);
		assert.deepEqual(patches, [{ admin: false }]);
	} finally { await page.close(); }
});

test('explicit integration kind hides replies without message metadata', async () => {
	const { page } = await setup();
	try {
		await page.goto(baseURL + '/messages/result-fixture');
		const detail = page.locator('.message-detail');
		await detail.getByText('Integration', { exact: true }).waitFor({ state: 'visible' });
		await detail.getByText('Replies are off for this sender', { exact: true }).waitFor();
		assert.equal(await detail.getByRole('textbox', { name: /reply/i }).count(), 0);
	} finally { await page.close(); }
});

test('legacy server and non-admin boss never get the admin switch', async () => {
	for (const [role, capabilities] of [['admin', false], ['manager', true], ['viewer', true]]) {
		const { page } = await setup(role, capabilities);
		try {
			await page.goto(baseURL + '/agents/builder-01');
			await page.getByRole('heading', { name: 'Builder One', exact: true }).waitFor();
			assert.equal(await page.getByRole('switch', { name: 'Admin capability' }).count(), 0);
			if (!capabilities) assert.equal(await page.getByLabel('Default priority').inputValue(), 'normal');
		} finally { await page.close(); }
	}
});

test('transcript keeps older pages on reconnect and navigates its image gallery', async () => {
	const { page } = await setup();
	let streamRequests = 0;
	let receivedOffset = null;
	const id = 'release-session';
	const make = (i) => ({
		id: 'entry-' + i, body: 'Transcript entry ' + i, agent_id: 'builder-01', direction: 'agent_to_boss',
		created_at: new Date(Date.UTC(2026, 9, 1, 0, 0, i)).toISOString(),
		metadata: i < 2 ? { file_url: baseURL + '/fixture/image-' + i + '.png' } : null
	});
	try {
		await page.route('**/api/sessions/*/stream**', (route) => {
			streamRequests++;
			return route.fulfill(streamRequests === 1 ? { status: 503 } : {
				contentType: 'text/event-stream', body: 'event: session_event\ndata: {"sequence":22}\n\n'
			});
		});
		await page.route('**/api/boss/messages?**', (route) => {
			const params = new URL(route.request().url()).searchParams;
			receivedOffset = params.get('offset') ?? receivedOffset;
			const rows = Array.from({ length: streamRequests > 1 ? 53 : 52 }, (_, index) => make(index)).reverse();
			const start = Number(params.get('offset') ?? 0);
			return route.fulfill({ json: { messages: rows.slice(start, start + 50), total: rows.length } });
		});
		await page.route('**/fixture/*.png', (route) => route.fulfill({ contentType: 'image/png', body: Buffer.from(
			'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jVqUAAAAASUVORK5CYII=', 'base64'
		) }));
		await page.goto(baseURL + '/sessions/' + id);
		await page.getByText(/Offline.*last updated/i).waitFor();
		await page.getByRole('button', { name: 'Load older messages' }).click();
		await page.getByRole('article', { name: 'Transcript entry 0', exact: true }).waitFor();
		assert.equal(receivedOffset, '50');
		await page.getByRole('article', { name: 'Transcript entry 52', exact: true }).waitFor();
		assert.equal(await page.getByRole('article', { name: 'Transcript entry 0', exact: true }).count(), 1);
		await page.getByRole('button', { name: /image-0.png/ }).click();
		const dialog = page.getByRole('dialog');
		await dialog.getByRole('button', { name: 'Next', exact: true }).click();
		assert.equal(await dialog.getByRole('img').getAttribute('alt'), 'image-1.png');
		await page.keyboard.press('ArrowLeft');
		assert.equal(await dialog.getByRole('img').getAttribute('alt'), 'image-0.png');
		await page.keyboard.press('Escape');
		await dialog.waitFor({ state: 'hidden' });
	} finally { await page.close(); }
});

test('management pages fit a 375 px viewport and narrow tables retain their labels', async () => {
	const { page } = await setup();
	try {
		for (const [path, landmark] of [
			['/delivery', page.getByText('No destinations yet', { exact: true })],
			['/delivery?tab=rules', page.getByText('^release', { exact: true })],
			['/access', page.getByRole('heading', { name: 'Agent access' })],
			['/audit', page.getByText('agent.update', { exact: true })],
			['/server', page.getByText('Healthy', { exact: true })],
			['/devices', page.getByText('Fixture browser', { exact: true })]
		]) {
			await page.goto(baseURL + path);
			await landmark.waitFor();
			assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), 375, path);
			if (path === '/audit' || path === '/delivery?tab=rules') {
				const cell = page.locator('td[data-label]').first();
				assert.equal(await cell.evaluate((node) => getComputedStyle(node).display), 'grid');
				assert.notEqual(await cell.evaluate((node) => getComputedStyle(node, '::before').content), 'none');
			}
		}
	} finally { await page.close(); }
});
