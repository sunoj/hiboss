// Type declarations for the cloudflare:test environment used by relay tests.

import type { D1Migration } from 'cloudflare:test';
import type { Env as RelayEnv } from '../src/types';

declare global {
  namespace Cloudflare {
    interface Env extends RelayEnv {
      TEST_MIGRATIONS: D1Migration[];
      WRANGLER_EXAMPLE: string;
    }
  }
}
