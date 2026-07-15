// Type declarations for cloudflare:test virtual module.
// Extends the current Cloudflare Vitest environment with HiBoss bindings.
// Depends on the worker Env contract and vitest-pool cloudflare:test types.

import type { Env as WorkerEnv } from './types';

declare global {
  namespace Cloudflare {
    interface Env extends WorkerEnv {
      TEST_MIGRATIONS: string;
    }
  }
}
