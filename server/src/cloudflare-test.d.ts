// Type declarations for cloudflare:test virtual module.
// Provides D1Database binding type for test env access.
// Depends on @cloudflare/workers-types.

import type { D1Database } from '@cloudflare/workers-types';

declare module 'cloudflare:test' {
  interface ProvidedEnv {
    DB: D1Database;
    TEST_MIGRATIONS: string;
  }
}
