// Vitest config for Cloudflare Workers integration tests.
// Uses @cloudflare/vitest-pool-workers for real D1 + workerd runtime.
// Depends on wrangler.toml for D1 binding definition.

import { defineConfig } from 'vitest/config';
import { cloudflarePool, cloudflareTest } from '@cloudflare/vitest-pool-workers';

const workerOptions = {
  wrangler: { configPath: './wrangler.toml' },
};

export default defineConfig({
  plugins: [cloudflareTest(workerOptions)],
  test: {
    globals: true,
    pool: cloudflarePool(workerOptions),
  },
});
