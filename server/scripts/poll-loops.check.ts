// Completeness gate: every timed loop, interval and DO alarm in server/src is in REPEAT_SITES.
// Also proves the scanner on each loop style and on an unregistered dummy loop.
// Depends on scripts/poll-loops.ts and src/read-budget/repeat-sites.ts; reads sources from disk.

import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, expect, it } from 'vitest';
import { findRepeatSites, isProductionSource } from './poll-loops';
import { REPEAT_SITES } from '../src/read-budget/repeat-sites';

const SRC = join(__dirname, '..', 'src');

function productionSources(): Map<string, string> {
  const sources = new Map<string, string>();
  const walk = (dir: string): void => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (isProductionSource(relative(SRC, path))) sources.set(relative(SRC, path), readFileSync(path, 'utf8'));
    }
  };
  walk(SRC);
  return sources;
}

function unregistered(sources: Map<string, string>): string[] {
  const known = new Set(REPEAT_SITES.map((site) => `${site.id}:${site.kind}`));
  return findRepeatSites(sources).filter((site) => !known.has(`${site.id}:${site.kind}`))
    .map((site) => `${site.kind} ${site.id} (line ${site.line})`);
}

describe('repeated-read registry completeness', () => {
  it('registers every timed loop, interval and alarm in server/src', () => {
    expect(unregistered(productionSources()), 'add each site to src/read-budget/repeat-sites.ts '
      + 'and meter it in src/read-budget/read-paths.ts').toEqual([]);
  });

  it('keeps no registry entry for a site that no longer exists', () => {
    const found = new Set(findRepeatSites(productionSources()).map((site) => `${site.id}:${site.kind}`));
    expect(REPEAT_SITES.filter((site) => !found.has(`${site.id}:${site.kind}`)).map((site) => site.id)).toEqual([]);
  });

  it('gives each registered site a metered path or a reason', () => {
    for (const site of REPEAT_SITES) expect(site.paths.length > 0 || !!site.unmetered, site.id).toBe(true);
  });

  it('fails on an unregistered dummy loop added beside the real sources', () => {
    const sources = productionSources();
    sources.set('routes/dummy-stream.ts', `export async function dummyLoop(env: Env) {
      for (;;) { await env.DB.prepare('SELECT * FROM messages').all(); await sleep(3_000); } }`);
    expect(unregistered(sources)).toEqual(['loop routes/dummy-stream.ts#dummyLoop (line 2)']);
  });
});

describe('repeat-site scanner', () => {
  const scan = (text: string) => findRepeatSites(new Map([['x.ts', text]])).map((site) => `${site.kind} ${site.id}`);

  it.each([
    ['while + inline promise timer', 'async function a() { while (open) { await poll(); await new Promise((r) => setTimeout(r, 3000)); } }'],
    ['while (true) + local delay', 'function delay(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }\n'
      + 'async function a() { while (true) { await poll(); await delay(1000); } }'],
    ['do/while + imported sleep wrapper', 'const pause = (ms) => sleep(ms);\nfunction sleep(ms) { return new Promise((done) => { setTimeout(() => done(), ms); }); }\n'
      + 'async function a() { do { await poll(); await pause(5); } while (open); }'],
    ['for (;;) + scheduler.wait', 'async function a() { for (;;) { await poll(); await scheduler.wait(100); } }'],
    ['for…of + delay', 'async function a(items) { for (const item of items) { await send(item); await delay(10); } }\n'
      + 'const delay = (ms) => new Promise((r) => setTimeout(r, ms));'],
  ])('detects %s', (_, text) => {
    expect(scan(text)).toContain('loop x.ts#a');
  });

  it('detects intervals, alarms and self-rescheduling timers', () => {
    expect(scan('function tick() { poll(); setTimeout(tick, 1000); }')).toEqual(['reschedule x.ts#tick']);
    expect(scan('function start() { setInterval(() => poll(), 1000); }')).toEqual(['interval x.ts#start']);
    expect(scan('class Room { async arm() { await this.ctx.storage.setAlarm(Date.now() + 5000); } }'))
      .toEqual(['alarm x.ts#Room.arm']);
  });

  it('names anonymous route handlers by their route', () => {
    expect(scan("routes.get('/wait', async (c) => { while (pending) await delay(1000); });\n"
      + 'const delay = (ms) => new Promise((r) => setTimeout(r, ms));')).toEqual(['loop x.ts#routes.get(/wait)']);
  });

  it('ignores untimed pagination loops and timeout guards', () => {
    expect(scan('async function a() { do { page = await next(page); } while (page.cursor); }')).toEqual([]);
    expect(scan('async function open() { await new Promise((resolve, reject) => { setTimeout(() => reject(new Error()), 10); }); }\n'
      + 'async function a() { while (retry) { await open(); } }')).toEqual([]);
  });
});
