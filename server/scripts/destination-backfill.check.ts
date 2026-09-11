// Executes the production-shaped destination migration fixture with real SQLite.
// Depends on Python standard-library sqlite3 and the Node Vitest pool.
import { spawnSync } from 'node:child_process';
import { expect, it } from 'vitest';

it('backfills seven configs, two bosses, session threads, and native destinations additively', () => {
  const result = spawnSync('python3', ['-B', 'scripts/destination_backfill.py'], { encoding: 'utf8' });
  expect(result.status, result.stdout + result.stderr).toBe(0);
});
