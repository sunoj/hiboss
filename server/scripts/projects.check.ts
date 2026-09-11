// Runs migration backfill fixtures against real SQLite before rollout.
// Exports Vitest cases; depends on Python standard-library unittest.
import { spawnSync } from 'node:child_process';
import { expect, it } from 'vitest';

it('passes four project backfill, preservation, collision, and constraint fixtures', () => {
  const result = spawnSync('python3', ['scripts/projects-backfill.py'], { encoding: 'utf8' });
  expect(result.status, result.stdout + result.stderr).toBe(0);
});
