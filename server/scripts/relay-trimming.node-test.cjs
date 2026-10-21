// Measures encrypted relay trimming with Node's advancing monotonic clock.
// Loads the production TypeScript sender with erased types and mocked HTTP.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const { webcrypto } = require('node:crypto');
const { performance } = require('node:perf_hooks');
const ts = require('typescript');

test('20,000-character relay fields finish within 100 ms and fit 2,048 bytes', async t => {
  let wire;
  const context = {
    exports: {}, crypto: webcrypto, TextEncoder, Uint8Array, structuredClone, atob, btoa,
    fetch: async (_url, init) => {
      wire = JSON.parse(init.body);
      return { ok: true };
    },
  };
  const source = readFileSync(`${__dirname}/../src/push/relay.ts`, 'utf8');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  });
  runInNewContext(compiled.outputText, context);
  const payload = { aps: { alert: { title: '🙂'.repeat(20000),
    subtitle: '秘密'.repeat(20000), body: 'x'.repeat(20000) },
    'interruption-level': 'passive', 'thread-id': 'boss', category: 'HIBOSS_MESSAGE' },
    messageId: 'large-message' };
  const started = performance.now();
  await context.exports.sendRelay('https://relay.test', 'a'.repeat(42) + 'A',
    'b'.repeat(42) + 'A', payload, 'message', '5');
  const elapsed = performance.now() - started;
  assert.ok(elapsed < 100, `relay send took ${elapsed.toFixed(2)} ms`);
  const bytes = Buffer.from(wire.ciphertext, 'base64url');
  assert.ok(bytes.length <= 2048);
  t.diagnostic(`relay send: ${elapsed.toFixed(2)} ms; ciphertext: ${bytes.length} bytes`);
  const key = await webcrypto.subtle.importKey('raw', Buffer.from('b'.repeat(42) + 'A', 'base64url'),
    'AES-GCM', false, ['decrypt']);
  const plain = await webcrypto.subtle.decrypt({ name: 'AES-GCM', iv: bytes.subarray(0, 12),
    additionalData: new TextEncoder().encode('hiboss-push-v1|message') }, key, bytes.subarray(12));
  const result = JSON.parse(new TextDecoder().decode(plain));
  assert.equal(result.messageId, payload.messageId);
  assert.equal(result.aps.category, payload.aps.category);
  assert.equal(payload.aps.alert.body.length, 20000);
});
