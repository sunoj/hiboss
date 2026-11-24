// Render every public page at desktop and mobile widths, light and dark, for review without a browser.
// Usage: node render-site.mjs <built-site-dir> <output-dir>   (built-site-dir comes from site/build.sh)
// Needs playwright-core on NODE_PATH and a local Chrome. Scripts are disabled, so the home page shows
// the native Island screenshot instead of the interactive demo and lazy images load.
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { mkdirSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';

const { chromium } = createRequire(import.meta.url)('playwright-core');
const [site, out] = process.argv.slice(2);
if (!site || !out) { console.error('usage: render-site.mjs <built-site-dir> <output-dir>'); process.exit(2); }
const PAGES = { home: '/', 'zh-home': '/zh/', download: '/download/', 'zh-download': '/zh/download/',
  'self-host': '/docs/self-host/', 'zh-self-host': '/zh/docs/self-host/', agents: '/docs/agents/',
  changelog: '/changelog/', privacy: '/privacy/', support: '/support/', 404: '/404.html' };
const WIDTHS = { desktop: [1440, 900, 1], mobile: [390, 844, 1.5] };
const TYPES = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript',
  '.svg': 'image/svg+xml', '.jpg': 'image/jpeg', '.png': 'image/png' };

const server = createServer(async (request, response) => {
  let path = normalize(decodeURIComponent(new URL(request.url, 'http://x').pathname));
  if (path.endsWith('/')) path += 'index.html';
  try {
    const body = await readFile(join(site, path));
    response.writeHead(200, { 'content-type': TYPES[extname(path)] ?? 'application/octet-stream' });
    response.end(body);
  } catch { response.writeHead(404); response.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome' });
let failures = 0;
for (const [device, [width, height, scale]] of Object.entries(WIDTHS)) {
  for (const theme of ['light', 'dark']) {
    const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: scale,
      colorScheme: theme, javaScriptEnabled: false, reducedMotion: 'reduce' });
    const page = await context.newPage();
    const offsite = [];
    page.on('request', r => { if (!r.url().startsWith(base)) offsite.push(r.url()); });
    for (const [name, path] of Object.entries(PAGES)) {
      await page.goto(base + path, { waitUntil: 'networkidle' });
      const facts = await page.evaluate(() => ({
        background: getComputedStyle(document.body).backgroundColor,
        overflow: document.documentElement.scrollWidth > innerWidth,
        broken: [...document.images].filter(i => !i.complete || !i.naturalWidth).map(i => i.currentSrc),
      }));
      const expected = theme === 'dark' ? 'rgb(14, 15, 18)' : 'rgb(242, 243, 245)';
      const problems = [facts.background !== expected && `background ${facts.background}`,
        facts.overflow && 'horizontal overflow', facts.broken.length && `broken images ${facts.broken}`,
        offsite.length && `off-site requests ${offsite}`].filter(Boolean);
      if (problems.length) { failures += 1; console.error(`FAIL ${name} ${device} ${theme}: ${problems.join('; ')}`); }
      await page.screenshot({ path: join(out, `${name}-${device}-${theme}.jpg`), fullPage: true,
        type: 'jpeg', quality: 64 });
      for (const narrow of [320, 768]) {
        await page.setViewportSize({ width: narrow, height });
        if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)) {
          failures += 1; console.error(`FAIL ${name} ${theme}: horizontal overflow at ${narrow}px`);
        }
      }
      await page.setViewportSize({ width, height });
      offsite.length = 0;
    }
    await context.close();
  }
}
await browser.close();
server.close();
console.log(`rendered ${Object.keys(PAGES).length * 4} images, ${failures} failed checks`);
process.exit(failures ? 1 : 0);
