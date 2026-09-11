// Run schema CLI integration checks in Node, separately from the Worker test pool.
// Exports Vitest configuration; depends on the existing Vitest toolchain.
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: { include: ['scripts/schema.check.ts'], environment: 'node' },
});
