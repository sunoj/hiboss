// Compose the App Store creative assets (product page header and search results image).
// One universal PNG per locale and variant, exactly 5244x2950 with no alpha, plus crop previews.
// Usage: node creative.mjs <output-dir>   (normally docs/design-marketing/app-store/creative)
// Needs playwright-core on NODE_PATH and a local Chrome; text uses the system fonts of this Mac.
// The island is the v4 scene artwork, placed unchanged; only sky, sea, sun and moon are extended.
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const { chromium } = createRequire(import.meta.url)('playwright-core');
const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(process.argv[2] ?? '');
if (!process.argv[2]) { console.error('usage: creative.mjs <output-dir>'); process.exit(2); }

export const CANVAS = { width: 5244, height: 2950 };
export const SAFE = { x: 1921, y: 660, width: 1402, height: 962 };
const center = { x: SAFE.x + SAFE.width / 2, y: SAFE.y + SAFE.height / 2 };
// Wide crops keep one full canvas dimension; tight crops give the safe area the share of the frame
// that the separate 21:9 header (1646 of 3840) and 3:2 search (2168 of 3840) specs give theirs.
const CROPS = {
  '21x9-wide': { width: 5244, height: 2247 }, '21x9-tight': { width: 3271, height: 1402 },
  '3x2-wide': { width: 4425, height: 2950 }, '3x2-tight': { width: 2483, height: 1655 },
};
const COPY = {
  'en-US': { lang: 'en', headline: ['Your agents ask.', 'You decide.'], server: ['Your server.', 'Your data.'] },
  'zh-Hans': { lang: 'zh-Hans', headline: ['智能体来问，', '你来拍板。'], server: ['你的服务器，', '你的数据。'] },
};
// Scene facts: which elements are background (dropped, then redrawn canvas-wide) and where the island sits.
const SCENES = {
  day: { file: 'island-day.svg', box: { x: 26, y: 188, width: 388, height: 264 }, sea: 372, scale: 2.1,
    drop: /url\(#daySky\)|url\(#sunGlow\)|#FFD46B|#FFFFFF|url\(#daySea\)|#9BE6EA/,
    sky: ['#8FD0F0', '#E8F6FB'], water: ['#35C6D0', '#169BB0'], wave: '#9BE6EA', ink: '#111317',
    orb: '#FFD46B', glow: 'rgba(255,231,163,.9)', stars: false },
  night: { file: 'island-night.svg', box: { x: 44, y: 18, width: 214, height: 128 }, sea: 118, scale: 3.8,
    drop: /url\(#nightSky\)|url\(#moonGlow\)|"#F6E7B8"|#E6D39C|#DCE6F0|url\(#nightSea\)|#3F8FA0/,
    sky: ['#0D1B2A', '#1D3B52'], water: ['#145566', '#0E3946'], wave: '#3F8FA0', ink: '#F2F3F5',
    orb: '#F6E7B8', glow: 'rgba(246,231,184,.4)', stars: true },
};

// A small seeded generator, so stars and waves are scattered the same way on every run.
function seeded(seed) {
  let state = seed;
  return () => {
    state = (state + 0x6D2B79F5) | 0;
    let value = Math.imul(state ^ (state >>> 15), 1 | state);
    value = (value + Math.imul(value ^ (value >>> 7), 61 | value)) ^ value;
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function island(scene) {
  const source = readFileSync(join(here, '../../design-v4/scenes', scene.file), 'utf8');
  const defs = source.match(/<defs>[\s\S]*?<\/defs>/)[0];
  const body = source.replace(/<defs>[\s\S]*?<\/defs>/, '').replace(/<\/?svg[^>]*>/g, '');
  const kept = body.match(/<(rect|circle|path|ellipse)\b[^>]*>(<\/\1>)?/g).filter(element => !scene.drop.test(element));
  return defs + kept.join('');
}

function page(locale, variant) {
  const scene = SCENES[variant.scene], copy = COPY[locale], lines = copy[variant.text];
  const cjk = copy.lang !== 'en';
  const bottom = SAFE.y + SAFE.height - 16;                       // island's lowest point
  const top = bottom - scene.box.height * scene.scale;            // island's highest point
  const left = center.x - (scene.box.x + scene.box.width / 2) * scene.scale;
  const horizon = top + (scene.sea - scene.box.y) * scene.scale;  // canvas y of the sea line
  const random = seeded(scene.stars ? 7 : 3);
  const inSafe = (x, y) => x > SAFE.x - 80 && x < SAFE.x + SAFE.width + 80 && y > SAFE.y - 80;
  const dots = scene.stars ? Array.from({ length: 90 }, () => {
    const x = random() * CANVAS.width, y = random() * (horizon - 160), r = 4 + random() * 6;
    return inSafe(x, y) ? '' : `<circle cx="${x}" cy="${y}" r="${r}" fill="#DCE6F0" opacity="${0.45 + random() * 0.5}"/>`;
  }).join('') : [[900, 520, 3.2], [4380, 980, 2.6], [1500, 1120, 2], [3620, 380, 2.2]].map(([x, y, s]) =>
    `<path transform="translate(${x} ${y}) scale(${s})" d="M0 44 q14 -22 38 -12 q12 -18 34 -6 q22 0 22 18 z" fill="#FFFFFF" opacity=".88"/>`).join('');
  const waves = Array.from({ length: 30 }, () => {
    const x = random() * CANVAS.width, y = horizon + 110 + random() * (CANVAS.height - horizon - 180);
    return `<path d="M${x} ${y} q40 -16 80 0" stroke="${scene.wave}" stroke-width="9" fill="none" stroke-linecap="round" opacity=".8"/>`;
  }).join('');
  return `<!doctype html><html lang="${copy.lang}"><meta charset="utf-8"><style>
    html, body { margin: 0; } body { width: ${CANVAS.width}px; height: ${CANVAS.height}px; overflow: hidden;
      position: relative; font-family: system-ui, "PingFang SC", sans-serif; background: ${scene.sky[0]}; }
    svg { position: absolute; inset: 0; }
    h1 { position: absolute; margin: 0; left: ${SAFE.x}px; width: ${SAFE.width}px; top: ${SAFE.y + 24}px;
      text-align: center; color: ${scene.ink}; font-size: ${cjk ? 150 : 158}px; line-height: ${cjk ? 1.16 : 1.03};
      letter-spacing: ${cjk ? 0 : '-0.034em'}; font-weight: 800; }
    h1 span { display: block; white-space: nowrap; } h1 .quiet { font-weight: 500; }
  </style><body><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CANVAS.width} ${CANVAS.height}">
    <defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${scene.sky[0]}"/>
      <stop offset="1" stop-color="${scene.sky[1]}"/></linearGradient>
      <linearGradient id="water" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${scene.water[0]}"/>
      <stop offset="1" stop-color="${scene.water[1]}"/></linearGradient>
      <radialGradient id="glow"><stop offset="0" stop-color="${scene.glow}"/><stop offset="1" stop-color="${scene.glow}" stop-opacity="0"/></radialGradient></defs>
    <rect width="${CANVAS.width}" height="${horizon}" fill="url(#sky)"/>
    <circle cx="4020" cy="560" r="520" fill="url(#glow)"/><circle cx="4020" cy="560" r="150" fill="${scene.orb}"/>
    ${dots}
    <rect y="${horizon}" width="${CANVAS.width}" height="${CANVAS.height - horizon}" fill="url(#water)"/>
    ${waves}
    <g transform="translate(${left} ${top - scene.box.y * scene.scale}) scale(${scene.scale})">${island(scene)}</g>
  </svg><h1><span class="quiet">${lines[0]}</span><span>${lines[1]}</span></h1></body></html>`;
}

function preview(asset, name, crop) {
  const x = Math.round(Math.min(Math.max(center.x - crop.width / 2, 0), CANVAS.width - crop.width));
  const y = Math.round(Math.min(Math.max(center.y - crop.height / 2, 0), CANVAS.height - crop.height));
  const k = 1600 / crop.width;
  return { height: Math.round(crop.height * k), html: `<!doctype html><meta charset="utf-8"><body style="margin:0;
    width:1600px;height:${crop.height * k}px;overflow:hidden;position:relative;font:22px system-ui">
    <img src="file://${asset}" style="position:absolute;width:${CANVAS.width * k}px;left:${-x * k}px;top:${-y * k}px">
    <div style="position:absolute;left:${(SAFE.x - x) * k}px;top:${(SAFE.y - y) * k}px;width:${SAFE.width * k}px;
      height:${SAFE.height * k}px;outline:3px dashed #C2410C"></div>
    <div style="position:absolute;left:8px;top:8px;background:#111317;color:#fff;padding:4px 10px">${name} · crop
      ${crop.width}×${crop.height} at ${x},${y} · dashed: art safe area</div></body>` };
}

const VARIANTS = { universal: { scene: 'day', text: 'headline' }, 'universal-self-hosted': { scene: 'night', text: 'server' } };
mkdirSync(join(out, 'previews'), { recursive: true });
const browser = await chromium.launch({ channel: 'chrome' });
const scratch = join(out, '.creative.html');
for (const locale of Object.keys(COPY)) {
  mkdirSync(join(out, locale), { recursive: true });
  for (const [name, variant] of Object.entries(VARIANTS)) {
    const asset = join(out, locale, `${name}.png`);
    const tab = await browser.newPage({ viewport: CANVAS, deviceScaleFactor: 1 });
    writeFileSync(scratch, page(locale, variant));
    await tab.goto('file://' + scratch, { waitUntil: 'load' });
    await tab.screenshot({ type: 'png', path: asset, omitBackground: false });
    for (const [cropName, crop] of Object.entries(CROPS)) {
      const view = preview(asset, `${locale}/${name} ${cropName}`, crop);
      writeFileSync(scratch, view.html);
      await tab.setViewportSize({ width: 1600, height: view.height });
      await tab.goto('file://' + scratch, { waitUntil: 'load' });
      await tab.locator('img').evaluate(image => image.decode());
      await tab.screenshot({ type: 'jpeg', quality: 80, path: join(out, 'previews', `${locale}-${name}-${cropName}.jpg`) });
    }
    await tab.close();
  }
}
rmSync(scratch);
await browser.close();
console.log(`creative assets written to ${out}`);
