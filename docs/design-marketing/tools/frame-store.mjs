// Compose App Store screenshots: a caption above a real, unretouched demo-mode capture.
// Usage: node frame-store.mjs <raw-iphone-dir> <raw-ipad-dir> <output-dir>
// Raw directories come from capture.sh. Captions live in ../app-store/captions.json.
// Needs playwright-core on NODE_PATH and a local Chrome; text uses the system fonts of this Mac.
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const { chromium } = createRequire(import.meta.url)('playwright-core');
const here = dirname(fileURLToPath(import.meta.url));
const [iphone, ipad, out] = process.argv.slice(2).map(path => resolve(path));
if (!iphone || !ipad || !out) {
  console.error('usage: frame-store.mjs <raw-iphone-dir> <raw-ipad-dir> <output-dir>'); process.exit(2);
}
const { frames } = JSON.parse(readFileSync(join(here, '../app-store/captions.json'), 'utf8'));
// u is the layout unit in pixels; every measure below is a multiple of it.
const DEVICES = {
  'iphone-6.9': { raw: iphone, width: 1320, height: 2868, u: 13.2, shot: 0.8, radius: 9, bezel: 1.5, top: 52 },
  'ipad-13': { raw: ipad, width: 2064, height: 2752, u: 17.2, shot: 0.84, radius: 3.6, bezel: 1.3, top: 40 },
};
const LOCALES = { 'en-US': 'en', 'zh-Hans': 'zh' };
const SKY = {
  light: { top: '#8FD0F0', mid: '#E8F6FB', ground: '#F2F3F5', ink: '#111317', sub: '#2A2E35',
    orb: '#FFD46B', glow: 'rgba(255,231,163,.85)' },
  dark: { top: '#0D1B2A', mid: '#1D3B52', ground: '#0E0F12', ink: '#F2F3F5', sub: '#C9CED6',
    orb: '#F6E7B8', glow: 'rgba(246,231,184,.32)' },
};
const escape = text => text.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

function page(device, frame, locale) {
  const d = DEVICES[device], sky = SKY[frame.appearance], [title, sub] = frame[locale];
  const source = join(d.raw, `${frame.scene}-${LOCALES[locale]}-${frame.appearance}.png`);
  if (!existsSync(source)) throw new Error(`missing capture ${source}`);
  const cjk = locale === 'zh-Hans';
  return `<!doctype html><html lang="${locale}"><meta charset="utf-8"><style>
    html, body { margin: 0; }
    body { width: ${d.width}px; height: ${d.height}px; overflow: hidden; position: relative;
      font-family: system-ui, "PingFang SC", sans-serif; color: ${sky.ink};
      background: radial-gradient(circle at 89% ${7 * d.u}px, ${sky.orb} 0 ${2.6 * d.u}px,
        ${sky.glow} ${2.7 * d.u}px, transparent ${11 * d.u}px),
        linear-gradient(${sky.top}, ${sky.mid} 46%, ${sky.ground} 78%); }
    header { padding: ${9 * d.u}px ${8 * d.u}px 0; }
    h1 { margin: 0; font-size: ${(cjk ? 8 : 8.2) * d.u}px; line-height: ${cjk ? 1.18 : 1.04};
      font-weight: 800; letter-spacing: ${cjk ? '0' : '-0.034em'}; white-space: pre-line; text-wrap: balance; max-width: 84%; }
    p { margin: ${2.4 * d.u}px 0 0; font-size: ${3.7 * d.u}px; line-height: 1.3; font-weight: 500;
      color: ${sky.sub}; max-width: 86%; }
    figure { position: absolute; margin: 0; left: 50%; top: ${d.top * d.u}px;
      width: ${d.shot * d.width}px; transform: translateX(-50%); box-sizing: content-box;
      border: ${d.bezel * d.u}px solid #0B0C0E; border-radius: ${(d.radius + d.bezel) * d.u}px;
      box-shadow: 0 ${4 * d.u}px ${9 * d.u}px ${-3 * d.u}px rgba(8,20,32,.55); background: #0B0C0E; }
    img { display: block; width: 100%; border-radius: ${d.radius * d.u}px; }
  </style><body><header><h1>${escape(title)}</h1><p>${escape(sub)}</p></header>
  <figure><img src="file://${source}" alt=""></figure></body></html>`;
}

mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome' });
const scratch = join(out, '.frame.html');
let count = 0;
for (const locale of Object.keys(LOCALES)) {
  for (const [device, d] of Object.entries(DEVICES)) {
    const target = join(out, locale, device);
    mkdirSync(target, { recursive: true });
    const tab = await browser.newPage({ viewport: { width: d.width, height: d.height }, deviceScaleFactor: 1 });
    const shown = frames.filter(frame => !(frame.skip ?? []).includes(device));
    for (const [index, frame] of shown.entries()) {
      writeFileSync(scratch, page(device, frame, locale));
      await tab.goto('file://' + scratch, { waitUntil: 'load' });
      await tab.locator('img').evaluate(image => image.decode());
      await tab.screenshot({ type: 'jpeg', quality: 88,
        path: join(target, `${String(index + 1).padStart(2, '0')}-${frame.name}.jpg`) });
      count += 1;
    }
    await tab.close();
  }
}
rmSync(scratch);
await browser.close();
console.log(`${count} frames written to ${out}`);
