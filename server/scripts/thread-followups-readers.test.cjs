// Regression coverage for dashboard reaction labels without a browser.
// Executes the existing dashboard helpers using Node's isolated VM context.
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const { test } = require('node:test');
const assert = require('node:assert/strict');

test('dashboard reads actor identities and legacy users', () => {
  const html = readFileSync(new URL('../src/dashboard.html', `file://${__filename}`), 'utf8');
  const source = html.slice(html.indexOf('function parseMetadata('),
    html.indexOf('function messageOptions('));
  const actual = runInNewContext(`${source}; messageReactions(message)`, {
    message: { metadata: { reactions: [
      { emoji: '👍', actor: 'agent', actor_id: 'agent-1' },
      { emoji: '🔥', actor: 'boss', actor_id: '123' },
      { emoji: '👍', user: 'Alice' },
    ] } },
  });
  assert.deepEqual(JSON.parse(JSON.stringify(actual)), [
    { emoji: '👍', user: 'agent: agent-1' },
    { emoji: '🔥', user: 'boss: 123' },
    { emoji: '👍', user: 'Alice' },
  ]);
});
