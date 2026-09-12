// Seven-agent backfill and unchanged child-table contract checks.
// Runs actual migrations in SQLite; depends on Python and Node Vitest.
import { spawnSync } from 'node:child_process';
import { expect, it } from 'vitest';
it('preserves seven agents, their bearer hashes and child tables while splitting admin capability', () => {
  const result = spawnSync('python3', ['-B', 'scripts/agent_keys_backfill.py'], { encoding: 'utf8' });
  expect(result.status, result.stdout + result.stderr).toBe(0);
});
