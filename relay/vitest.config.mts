// Vitest config for the push relay Worker on the Cloudflare Workers pool.
// Runs tests in workerd with a local D1 binding seeded from migrations/.
// Needs no wrangler.toml, so a fresh checkout can run the suite; tests read the example's text.

import { readFileSync } from 'node:fs';
import { defineConfig } from 'vitest/config';
import { cloudflarePool, cloudflareTest, readD1Migrations } from '@cloudflare/vitest-pool-workers';

const migrations = await readD1Migrations(new URL('./migrations', import.meta.url).pathname);
const wranglerExample = readFileSync(new URL('./wrangler.toml.example', import.meta.url), 'utf8');

const workerOptions = {
  main: './src/index.ts',
  miniflare: {
    compatibilityDate: '2025-01-01',
    d1Databases: ['DB'],
    bindings: { TEST_MIGRATIONS: migrations, WRANGLER_EXAMPLE: wranglerExample },
  },
};

export default defineConfig({
  plugins: [cloudflareTest(workerOptions)],
  test: {
    globals: true,
    testTimeout: 30_000,
    fileParallelism: false,
    setupFiles: ['./test/apply-migrations.ts'],
    pool: cloudflarePool(workerOptions),
  },
});
