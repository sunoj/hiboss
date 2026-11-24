// Compose the promotional cards: an Open Graph card (1200x630) and a square social card (1080x1080),
// in English and Simplified Chinese. Every phone shows a real, unretouched demo-mode capture.
// Usage: node promo.mjs <raw-iphone-dir> <output-dir>   (raw dir comes from capture.sh)
// Needs playwright-core on NODE_PATH and a local Chrome; text uses the system fonts of this Mac.
import { createRequire } from 'node:module';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const { chromium } = createRequire(import.meta.url)('playwright-core');
const here = dirname(fileURLToPath(import.meta.url));
const [raw, out] = process.argv.slice(2).map(path => resolve(path));
if (!raw || !out) { console.error('usage: promo.mjs <raw-iphone-dir> <output-dir>'); process.exit(2); }
const icon = resolve(here, '../../../site/assets/icon.png');
const COPY = {
  en: { lang: 'en', ask: 'Your agents ask.', decide: 'You decide.',
    sub: 'Answer AI agents from iPhone, Mac or chat.', tag: 'Open source and self-hosted',
    point: 'Silence is never approval.',
    detail: 'When a deadline picks a default, HiBoss says so. It never counts as your answer.' },
  zh: { lang: 'zh-Hans', ask: '智能体来问，', decide: '你来拍板。',
    sub: '在 iPhone、Mac 或聊天应用里回复 AI 智能体。', tag: '开源，自托管',
    point: '不回复，绝不算批准。',
    detail: '到点自动选的默认项，HiBoss 会明确标注，绝不算你的回答。' },
};
const BASE = `html, body { margin: 0; } body { overflow: hidden; position: relative;
  font-family: system-ui, "PingFang SC", sans-serif; }
  .brand { display: flex; align-items: center; gap: 16px; font-weight: 750; letter-spacing: -0.02em; }
  .brand img { border-radius: 22%; }
  .phone { position: absolute; border: 9px solid #0B0C0E; background: #0B0C0E; border-radius: 52px;
    box-shadow: 0 30px 70px -24px rgba(8,20,32,.6); }
  .phone img { display: block; width: 100%; border-radius: 43px; }`;

function og(c) {
  const cjk = c.lang !== 'en';
  return `<!doctype html><html lang="${c.lang}"><meta charset="utf-8"><style>${BASE}
  body { width: 1200px; height: 630px; color: #111317;
    background: radial-gradient(circle at 1110px 96px, #FFD46B 0 30px, rgba(255,231,163,.85) 31px, transparent 130px),
      linear-gradient(#8FD0F0, #E8F6FB 70%, #F2F3F5); }
  main { position: absolute; left: 76px; top: 70px; width: 640px; }
  .brand { font-size: 34px; } .brand img { width: 60px; height: 60px; }
  h1 { margin: 64px 0 0; font-size: ${cjk ? 78 : 82}px; line-height: ${cjk ? 1.16 : 1.02};
    letter-spacing: ${cjk ? 0 : '-0.034em'}; font-weight: 800; }
  h1 span { display: block; } h1 .ask { font-weight: 500; }
  p { margin: 30px 0 0; font-size: 28px; white-space: nowrap; line-height: 1.3; color: #2A2E35; font-weight: 500; }
  .tag { margin-top: 22px; font-size: 23px; color: #4A505A; }
  .phone { left: 770px; top: 64px; width: 340px; }
  </style><body><main><div class="brand"><img src="file://${icon}" alt="">HiBoss</div>
  <h1><span class="ask">${c.ask}</span><span>${c.decide}</span></h1><p>${c.sub}</p><p class="tag">${c.tag}</p></main>
  <div class="phone"><img src="file://${join(raw, `today-${c.lang === 'en' ? 'en' : 'zh'}-light.png`)}" alt=""></div></body></html>`;
}

function square(c) {
  const cjk = c.lang !== 'en';
  return `<!doctype html><html lang="${c.lang}"><meta charset="utf-8"><style>${BASE}
  body { width: 1080px; height: 1080px; color: #F2F3F5;
    background: radial-gradient(circle at 950px 120px, #F6E7B8 0 32px, rgba(246,231,184,.32) 33px, transparent 140px),
      linear-gradient(#0D1B2A, #1D3B52 62%, #0E0F12); }
  main { position: absolute; left: 80px; top: 76px; width: 800px; }
  .brand { font-size: 32px; } .brand img { width: 56px; height: 56px; }
  h1 { margin: 52px 0 0; font-size: ${cjk ? 76 : 84}px; line-height: ${cjk ? 1.16 : 1.02};
    letter-spacing: ${cjk ? 0 : '-0.034em'}; font-weight: 800; text-wrap: balance; }
  p { margin: 26px 0 0; font-size: 31px; line-height: 1.32; color: #C9CED6; font-weight: 500; max-width: 760px; }
  .phone { left: 250px; top: 480px; width: 580px; border-width: 14px; border-radius: 86px; }
  .phone img { border-radius: 72px; }
  </style><body><main><div class="brand"><img src="file://${icon}" alt="">HiBoss</div>
  <h1>${c.point}</h1><p>${c.detail}</p></main>
  <div class="phone"><img src="file://${join(raw, `decision-${c.lang === 'en' ? 'en' : 'zh'}-dark.png`)}" alt=""></div></body></html>`;
}

mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome' });
const scratch = join(out, '.card.html');
for (const [key, copy] of Object.entries(COPY)) {
  for (const [name, width, height, build] of [['og', 1200, 630, og], ['square', 1080, 1080, square]]) {
    const tab = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
    writeFileSync(scratch, build(copy));
    await tab.goto('file://' + scratch, { waitUntil: 'load' });
    await Promise.all((await tab.locator('img').all()).map(image => image.evaluate(node => node.decode())));
    await tab.screenshot({ type: 'jpeg', quality: 86, path: join(out, `${name}-${key}.jpg`) });
    await tab.close();
  }
}
rmSync(scratch);
await browser.close();
console.log(`cards written to ${out}`);
