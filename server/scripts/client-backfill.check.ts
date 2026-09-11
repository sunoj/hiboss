// Runs seeded SQLite migration assertions against the actual migration files.
// Depends on Python standard-library sqlite3 and the Node Vitest pool.
import { spawnSync } from 'node:child_process';
import { expect, it } from 'vitest';

it('backfills clients, signing keys, and push devices without changing token hashes', () => {
  const result = spawnSync('python3', ['-B', 'scripts/client_backfill.py'], { encoding: 'utf8' });
  expect(result.status, result.stdout + result.stderr).toBe(0);
});
