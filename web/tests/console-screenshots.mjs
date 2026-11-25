// Captures the seven redesigned console surfaces with deterministic mock data.
// Run headless on the remote build box against vite preview.

import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { mockApi } from './console-fixture.mjs';

if (!process.env.HIBOSS_REMOTE_E2E) throw new Error('Run on an authorized remote build box');
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const baseURL = process.env.WEB_URL || 'http://127.0.0.1:4178';
const output = process.env.CONSOLE_SCREENSHOTS || '../docs/internal/web-console';
const screens = [
	['today', '/', 'Today'],
	['decision', '/messages/decision-fixture?from=today', 'Deploy migration 0052 to production?'],
	['messages', '/messages/result-fixture', 'Market warning on Base'],
	['sessions', '/sessions/release-session', 'atlas-api · release/v2.4'],
	['agents', '/agents', 'Agents'],
	['access', '/access', 'People & access'],
	['connect', '/connect', 'Connect this browser']
];

async function assertTypography(page, heading, name) {
	const title = page.getByRole('heading', { name: heading, exact: true });
	const computed = await title.evaluate((node) => {
		const style = getComputedStyle(node);
		return { weight: style.fontWeight, size: style.fontSize };
	});
	assert.deepEqual(computed, { weight: '700', size: '30px' }, name + ' title typography');
	const session = await page.context().newCDPSession(page);
	try {
		await session.send('DOM.enable');
		await session.send('CSS.enable');
		const { root } = await session.send('DOM.getDocument');
		const { nodeIds } = await session.send('DOM.querySelectorAll', { nodeId: root.nodeId, selector: 'h1' });
		const h1 = await title.textContent();
		const visibleIndex = await page.locator('h1').evaluateAll((nodes, text) =>
			nodes.findIndex((node) => node.textContent === text && node.getClientRects().length), h1);
		const { fonts } = await session.send('CSS.getPlatformFontsForNode', { nodeId: nodeIds[visibleIndex] });
		assert(fonts.some(({ glyphCount, postScriptName }) => glyphCount > 0 && /bold/i.test(postScriptName)),
			JSON.stringify(fonts));
	} finally {
		await session.detach();
	}
}

async function assertMobileClearance(page) {
	const metrics = await page.evaluate(() => {
		const main = document.querySelector('#main');
		const bar = document.querySelector('.shell > nav');
		window.scrollTo(0, document.documentElement.scrollHeight);
		return {
			horizontal: document.documentElement.scrollWidth <= innerWidth,
			contentEnd: main.lastElementChild.getBoundingClientRect().bottom,
			tabTop: bar.getBoundingClientRect().top,
			padding: parseFloat(getComputedStyle(main).paddingBottom),
			tabHeight: bar.offsetHeight
		};
	});
	assert(metrics.horizontal, 'phone content overflows horizontally');
	assert(metrics.padding >= metrics.tabHeight, JSON.stringify(metrics));
	// A short page may stretch its wrapper down to fill the viewport.
	assert(metrics.contentEnd <= metrics.tabTop, JSON.stringify(metrics));
	await page.evaluate(() => window.scrollTo(0, 0));
}

async function capture(browser, width, colorScheme, [name, path, heading]) {
	const page = await browser.newPage({ viewport: { width, height: width === 375 ? 812 : 900 }, colorScheme });
	const errors = [];
	page.on('pageerror', (error) => errors.push(error.message));
	try {
		await mockApi(page);
		await page.addInitScript(({ baseURL, connect }) => {
			localStorage.setItem('hiboss.locale', 'en');
			if (!connect) localStorage.setItem('hiboss.web.connection', JSON.stringify({
				baseUrl: baseURL, token: 'fixture', boss: { id: 'boss', name: 'Robin', role: 'admin' }
			}));
		}, { baseURL, connect: name === 'connect' });
		await page.goto(baseURL + path);
		await page.getByRole('heading', { name: heading, exact: true }).waitFor();
		if (name === 'today') {
			await page.getByRole('button', { name: 'Deploy', exact: true }).waitFor();
			assert.equal(await page.locator('.provenance time').first().innerText(), '18 min left');
			await page.getByText('No answer in 18 min picks “Not yet”. That is not approval.', { exact: true }).waitFor();
			const second = page.getByRole('link', { name: /Staging replay passed/ });
			assert.equal(await second.evaluate((node) => getComputedStyle(node).borderBlockStartWidth), '1px');
		}
		if (name === 'messages') {
			await page.getByRole('article', { name: 'Card: Liquidation monitor' }).waitFor();
			await page.getByRole('button', { name: 'Copy', exact: true }).waitFor();
		}
		if (name === 'access') await page.getByRole('heading', { name: 'Agent access' }).waitFor();
		if (name === 'connect') await page.getByLabel('Pairing code').waitFor();
		await assertTypography(page, heading, name);
		if (width === 375 && ['today', 'messages', 'sessions'].includes(name)) await assertMobileClearance(page);
		assert.deepEqual(errors, [], name + ' page errors');
		const file = output + '/' + name + '-' + colorScheme + '-' + width + '.png';
		await page.screenshot({ path: file, fullPage: true, animations: 'disabled' });
		console.info(file);
	} finally {
		await page.close();
	}
}

await mkdir(output, { recursive: true });
const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM });
try {
	for (const width of [1280, 375]) {
		for (const colorScheme of ['light', 'dark']) {
			for (const screen of screens) await capture(browser, width, colorScheme, screen);
		}
	}
} finally {
	await browser.close();
}
