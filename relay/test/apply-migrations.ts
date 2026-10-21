// Vitest setup: applies relay migrations to the test D1 database before each file.

import { applyD1Migrations, env } from 'cloudflare:test';

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
