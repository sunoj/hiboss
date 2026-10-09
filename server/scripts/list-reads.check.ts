// Run the production-sized SQLite query-plan and result-parity regression.
// Uses Python SQLite for plans/parity; the standalone --scanstats run measures visits.
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';

it('bounds dashboard page visits and preserves results on 30,044 messages', () => {
  const result = spawnSync('python3', ['-B', 'scripts/list-reads.py', '--check'], { encoding: 'utf8' });
  expect(result.status, result.stdout + result.stderr).toBe(0);
}, 30_000);

it('gates Worker publication on successful remote migrations', () => {
  const config = JSON.parse(readFileSync('package.json', 'utf8')) as { scripts: { deploy: string } };
  expect(config.scripts.deploy.split(/\s*&&\s*/)).toEqual([
    'wrangler d1 migrations apply hiboss-db --remote', 'wrangler deploy',
  ]);
});
