// Runs scripts/d1-read-watch.mjs against saved one-day insights with stubbed wrangler and hiboss.
// Covers: a scanning day alerts and exits 1, a healthy day is quiet, unreadable insights exit 2.
// Never reaches Cloudflare or HiBoss: both commands are local Node stubs in a temp directory.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { mkdtempSync, readFileSync, writeFileSync, existsSync } = require('node:fs');
const { join } = require('node:path');
const { tmpdir } = require('node:os');

const SCRIPT = join(__dirname, 'd1-read-watch.mjs');
const FIXTURES = join(__dirname, 'fixtures');

function run(fixture, options = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'd1-watch-'));
  const calls = join(dir, 'calls.jsonl');
  const wrangler = join(dir, 'wrangler.cjs');
  writeFileSync(wrangler, `const fs = require('node:fs');
fs.appendFileSync(${JSON.stringify(calls)}, JSON.stringify(['wrangler', ...process.argv.slice(2)]) + '\\n');
if (${options.fail === true}) { console.error('Authentication error [code: 10000]'); process.exit(1); }
process.stdout.write('npm warn exec installing wrangler\\n' + fs.readFileSync(${JSON.stringify(fixture ?? '')}, 'utf8'));`);
  const hiboss = join(dir, 'hiboss.cjs');
  writeFileSync(hiboss, `require('node:fs').appendFileSync(${JSON.stringify(calls)},
  JSON.stringify(['hiboss', ...process.argv.slice(2)]) + '\\n');`);
  const result = spawnSync(process.execPath, [SCRIPT], {
    encoding: 'utf8',
    env: { ...process.env, WRANGLER: `${process.execPath} ${wrangler}`, HIBOSS: `${process.execPath} ${hiboss}` },
  });
  const log = existsSync(calls) ? readFileSync(calls, 'utf8').trim().split('\n').map(line => JSON.parse(line)) : [];
  return { ...result, wrangler: log.filter(call => call[0] === 'wrangler'), hiboss: log.filter(call => call[0] === 'hiboss') };
}

test('a day of full-scan polls alerts through hiboss and exits 1', () => {
  const result = run(join(FIXTURES, 'd1-insights-scan-1d.json'));
  assert.equal(result.status, 1, result.stderr);
  assert.equal(result.hiboss.length, 1);
  const [, verb, title, ...rest] = result.hiboss[0];
  assert.equal(verb, 'send');
  assert.match(title, /^D1 rows read over budget: 1,307,793,794 in 1d$/);
  const content = rest[rest.indexOf('--content') + 1];
  assert.match(content, /total 1,307,793,794 rows read\/day > 250,000,000/);
  assert.match(content, /query 803,030,013 rows \(59,248 runs × 13,553 avg\)/);
  assert.match(content, /query 451,309,153 rows/);
});

test('a healthy day logs one line, sends nothing and exits 0', () => {
  const result = run(join(FIXTURES, 'd1-insights-healthy-1d.json'));
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(result.hiboss, []);
  assert.equal(result.stdout, 'd1-read-watch: ok 63,428,650 rows read in 1d across 10 statements\n');
});

test('queries both rankings for the last day of hiboss-db', () => {
  const result = run(join(FIXTURES, 'd1-insights-healthy-1d.json'));
  assert.deepEqual(result.wrangler.map(call => call.slice(1)), ['reads', 'count'].map(sortBy => [
    'd1', 'insights', 'hiboss-db', '--time-period', '1d', '--sort-by', sortBy, '--limit', '100', '--json']));
});

test('a hot scan alerts even while the daily total is small', async () => {
  const { evaluate } = await import(SCRIPT);
  const row = { query: 'SELECT * FROM messages WHERE agent_id IN (?)', avgRowsRead: 9_000, numberOfTimesRun: 6_000, totalRowsRead: 54_000_000 };
  assert.deepEqual(evaluate([{ ...row, totalRowsRead: 4_000_000, numberOfTimesRun: 6_000, avgRowsRead: 2_500 }]).breaches,
    ['hot scan 4,000,000 rows (6,000 runs × 2,500 avg): SELECT * FROM messages WHERE agent_id IN (?)']);
  assert.match(evaluate([row]).breaches.join('\n'), /^query 54,000,000 rows/);
});

test('unreadable insights alert and exit 2', () => {
  const result = run(null, { fail: true });
  assert.equal(result.status, 2);
  assert.equal(result.hiboss.length, 1);
  assert.match(result.hiboss[0][2], /could not read insights/);
});
