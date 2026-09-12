// Remote-only browser coverage of project editing, confirmation and locale states.
// Run with node --test; requires PLAYWRIGHT_MODULE and a running console on WEB_URL.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';

if (!process.env.HIBOSS_REMOTE_E2E) throw new Error('Run only on an authorized grok box');
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const baseURL = process.env.WEB_URL || 'http://127.0.0.1:4178';
let browser;
before(async () => { browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM }); });
after(async () => { await browser?.close(); });

function inventory() {
  return ['source', 'target'].map(slug => ({ id: slug, slug, display_name: slug,
    aliases: [slug], session_count: 1, last_seen_at: '2026-09-12 00:00:00', last_post_at: null, repo_url: null }));
}

async function setup(role = 'admin', viewport = { width: 1280, height: 900 }) {
  const page = await browser.newPage({ viewport });
  let projects = inventory();
  const patches = [];
  await page.addInitScript(({ baseURL, role }) => {
    localStorage.setItem('hiboss.web.connection', JSON.stringify({ baseUrl: baseURL, token: 'fixture', boss: { id: 'boss', name: 'Boss', role } }));
    localStorage.setItem('hiboss.locale', 'en');
  }, { baseURL, role });
  await page.route('**/api/boss/projects**', async route => {
    if (route.request().method() === 'PATCH') {
      const id = route.request().url().split('/').at(-1);
      const patch = route.request().postDataJSON();
      patches.push({ id, ...patch });
      if (patch.merge_into) {
        const source = projects.find(p => p.id === id);
        const target = projects.find(p => p.id === patch.merge_into);
        target.aliases.push(...source.aliases);
        target.session_count += source.session_count;
        projects = projects.filter(p => p.id !== id);
      } else projects.find(p => p.id === id).display_name = patch.display_name;
      return route.fulfill({ json: { ok: true } });
    }
    return route.fulfill({ json: { projects } });
  });
  await page.goto(`${baseURL}/projects`);
  await page.getByRole('heading', { name: 'source', exact: true }).waitFor();
  return { page, patches };
}

test('rename persists, cancelled merge sends nothing, confirmed merge moves source to target', async () => {
  const { page, patches } = await setup();
  try {
    const source = page.locator('li').filter({ has: page.getByRole('heading', { name: 'source', exact: true }) });
    await source.getByLabel('Display name', { exact: true }).fill('Source Display');
    await source.getByRole('button', { name: 'Save name', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('input')?.value === 'Source Display');
    await source.getByRole('combobox', { name: 'Merge into', exact: true }).selectOption('target');
    page.once('dialog', dialog => dialog.dismiss());
    await source.getByRole('button', { name: 'Merge', exact: true }).click();
    assert.equal(patches.length, 1);
    page.once('dialog', async dialog => {
      assert.match(dialog.message(), /source.*target/);
      await dialog.accept();
    });
    await source.getByRole('button', { name: 'Merge', exact: true }).click();
    await page.getByRole('heading', { name: 'source', exact: true }).waitFor({ state: 'detached' });
    assert.deepEqual(patches, [{ id: 'source', display_name: 'Source Display' }, { id: 'source', merge_into: 'target' }]);
    await page.reload();
    await page.getByRole('heading', { name: 'target', exact: true }).waitFor();
    assert.equal(await page.getByRole('heading', { name: 'source', exact: true }).count(), 0);
  } catch (error) {
    throw new Error(`${error}\nVisible page: ${await page.locator('body').innerText()}`);
  } finally { await page.close(); }
});

test('four locales render project management labels', async () => {
  const { page } = await setup();
  try {
    for (const [locale, title, displayName] of [
      ['en', 'Projects', 'Display name'], ['zh-CN', '项目', '显示名称'],
      ['ja', 'プロジェクト', '表示名'], ['ko', '프로젝트', '표시 이름']
    ]) {
      await page.locator('.language select').selectOption(locale);
      await page.getByRole('heading', { name: title, exact: true }).waitFor();
      assert.equal(await page.getByLabel(displayName, { exact: true }).count(), 2);
    }
  } finally { await page.close(); }
});

test('mobile controls stay reachable without horizontal overflow', async () => {
  const { page } = await setup('admin', { width: 390, height: 844 });
  try {
    await page.getByRole('button', { name: 'Merge', exact: true }).last().scrollIntoViewIfNeeded();
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    await mkdir('output/playwright', { recursive: true });
    await page.screenshot({ path: 'output/playwright/projects-mobile.png', fullPage: true });
  } finally { await page.close(); }
});

test('viewers see the inventory without edit or merge controls', async () => {
  const { page, patches } = await setup('viewer');
  try {
    assert.equal(await page.getByRole('button', { name: 'Save name', exact: true }).count(), 0);
    assert.equal(await page.getByRole('button', { name: 'Merge', exact: true }).count(), 0);
    assert.equal(patches.length, 0);
  } finally { await page.close(); }
});
