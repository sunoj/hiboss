// Verify schema parity and that meaningful drift survives SQL normalization.
// Runs the same SQLite comparison as check:schema; depends on Vitest and Node APIs.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, describe, expect, it } from 'vitest';

const directory = mkdtempSync(join(tmpdir(), 'hiboss-schema-test-'));
const schema = readFileSync('schema.sql', 'utf8');
afterAll(() => rmSync(directory, { recursive: true, force: true }));

function check(sql: string): { status: number | null; output: string } {
  const path = join(directory, 'schema.sql');
  writeFileSync(path, sql);
  const result = spawnSync('sh', ['scripts/check-schema.sh', '--schema', path], { encoding: 'utf8' });
  if (result.error) throw result.error;
  return { status: result.status, output: result.stdout + result.stderr };
}

describe('consolidated schema', () => {
  it('matches every migration on two fresh databases', () => {
    const result = check(schema);
    expect(result.status, result.output).toBe(0);
  });

  it('ignores formatting, comments, identifier quotes and IF NOT EXISTS', () => {
    const cosmetic = schema.replaceAll('CREATE TABLE IF NOT EXISTS', 'CREATE TABLE')
      .replaceAll('CREATE TABLE ', 'CREATE TABLE IF NOT EXISTS ')
      .replace('CREATE TABLE IF NOT EXISTS api_keys', 'CREATE TABLE IF NOT EXISTS "api_keys"')
      .replaceAll('key_hash TEXT', '`key_hash`\n TEXT /* formatting */')
      .replaceAll('callback_url TEXT', '[callback_url] TEXT');
    const result = check(cosmetic);
    expect(result.status, result.output).toBe(0);
  });

  it.each([
    ['index', 'ON messages(target_agent_id, created_at)', 'ON messages(target_agent_id)'],
    ['default', "DEFAULT 'normal'", "DEFAULT 'high'"],
    ['literal whitespace', "DEFAULT 'normal'", "DEFAULT 'normal  '"],
    ['literal case', "DEFAULT 'normal'", "DEFAULT 'NORMAL'"],
    ['literal SQL syntax', "DEFAULT 'normal'", "DEFAULT 'normal; -- IF NOT EXISTS'"],
    ['CHECK', "CHECK (blocking IN (0, 1))", "CHECK (blocking IN (0, 1, 2))"],
    ['foreign key', 'REFERENCES panels(panel_id)', 'REFERENCES panels(title)'],
    ['unique constraint', 'key_hash TEXT NOT NULL UNIQUE', 'key_hash TEXT NOT NULL'],
  ])('rejects %s drift with a SQL diff', (_label, before, after) => {
    expect(schema).toContain(before);
    const result = check(schema.replace(before, after));
    expect(result.status).toBe(1);
    expect(result.output).toContain('--- migrations');
    expect(result.output).toContain('+++ schema.sql');
  });

  it('regenerates an already truthful document without changing it', () => {
    const result = spawnSync('sh', ['scripts/check-schema.sh', '--regenerate'], { encoding: 'utf8' });
    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout).toBe('');
  });

  it('repairs drift with a targeted patch and preserves surrounding documentation', () => {
    const path = join(directory, 'repair.sql');
    const documented = schema.replace('-- Agent authentication', '-- Agent authentication\n-- Keep this note.');
    writeFileSync(path, documented.replace("DEFAULT 'normal'", "DEFAULT 'normal; -- drift'"));
    const generated = spawnSync('sh', ['scripts/check-schema.sh', '--regenerate', '--schema', path], { encoding: 'utf8' });
    expect(generated.status, generated.stderr).toBe(0);
    const patched = spawnSync('patch', [path], { input: generated.stdout, encoding: 'utf8' });
    expect(patched.status, patched.stderr).toBe(0);
    expect(readFileSync(path, 'utf8')).toBe(documented);
  });
});
