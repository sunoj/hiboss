// Runs migration backfill fixtures against real SQLite before rollout.
// Exports Vitest cases; depends on Python standard-library unittest.
import { spawnSync } from 'node:child_process';
import { expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { projectSlug } from '../src/projects';

it('preserves phase 3b posts, likes and messages and rejects uncopied profiles', () => {
  const result = spawnSync('python3', ['scripts/project-surfaces.py'], { encoding: 'utf8' });
  expect(result.status, result.stdout + result.stderr).toBe(0);
});

it('passes six project backfill, preservation, merge, collision and constraint fixtures', () => {
  const result = spawnSync('python3', ['scripts/projects-backfill.py'], { encoding: 'utf8' });
  expect(result.status, result.stdout + result.stderr).toBe(0);
});

it('uses exactly the migration normalization for ASCII, Unicode, controls and punctuation', () => {
  const inputs = ['Hello World', 'hello--world', "Ming's Repo", 'İstanbul', 'Kelvin', '项目', '!!!', '', '\t \n', '\u00a0Repo\u2003', 'A_B-1', 'x'.repeat(256),
    ...Array.from({ length: 255 }, (_, code) => `A${String.fromCharCode(code + 1)}Z`)];
  const migration = readFileSync('migrations/0043_projects.sql', 'utf8');
  const sql = migration.slice(migration.indexOf('WITH RECURSIVE normalized'), migration.indexOf('-- Double dash'));
  const result = spawnSync('python3', ['-c', `
import json, sqlite3, sys
data = json.load(sys.stdin)
db = sqlite3.connect(':memory:')
db.execute('CREATE TABLE _project_sources (value TEXT PRIMARY KEY, slug TEXT, base TEXT)')
db.executemany('INSERT INTO _project_sources (value) VALUES (?)', [(v,) for v in data['inputs']])
db.executescript(data['sql'])
print(json.dumps([db.execute('SELECT base FROM _project_sources WHERE value = ?', (v,)).fetchone()[0] for v in data['inputs']]))
`], { input: JSON.stringify({ inputs, sql }), encoding: 'utf8' });
  expect(result.status, result.stderr).toBe(0);
  expect(JSON.parse(result.stdout)).toEqual(inputs.map(projectSlug));
});
