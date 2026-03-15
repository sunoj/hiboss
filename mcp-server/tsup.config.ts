// Purpose: Configure tsup for the hiboss MCP server CLI bundle.
// Exports: default tsup build configuration.
// Dependencies: tsup defineConfig helper and node-targeted bundling.
import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['esm'],
  clean: true,
  banner: { js: '#!/usr/bin/env node' },
  target: 'node22',
  minify: false,
});
