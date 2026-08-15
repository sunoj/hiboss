// Vitest config for Cloudflare Workers integration tests.
// Uses @cloudflare/vitest-pool-workers for real D1 + workerd runtime.
// Depends on wrangler.toml for D1 binding definition.

import { defineConfig } from 'vitest/config';
import { cloudflarePool, cloudflareTest } from '@cloudflare/vitest-pool-workers';

const workerOptions = {
  wrangler: { configPath: './wrangler.toml' },
  miniflare: { bindings: { STREAM_POLL_INTERVAL_MS: '25' } },
};

export default defineConfig({
  plugins: [cloudflareTest(workerOptions)],
  test: {
    globals: true,
    // Worker stream tests use the injected 25ms poll interval; this timeout covers D1 setup.
    testTimeout: 15_000,
    // Serialize worker files so concurrent Miniflare runtimes do not starve D1 setup.
    fileParallelism: false,
    pool: cloudflarePool(workerOptions),
  },
});
