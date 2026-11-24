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
		if (name === 'today') await page.getByRole('button', { name: 'Deploy', exact: true }).waitFor();
		if (name === 'messages') {
			await page.getByRole('article', { name: 'Card: Liquidation monitor' }).waitFor();
			await page.getByRole('button', { name: 'Copy', exact: true }).waitFor();
		}
		if (name === 'access') await page.getByRole('heading', { name: 'Agent access' }).waitFor();
		if (name === 'connect') await page.getByLabel('Pairing code').waitFor();
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
