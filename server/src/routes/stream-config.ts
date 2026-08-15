// Shared stream timing configuration for production and worker integration tests.
// Exports poll defaults and validated environment override resolution.
// Depends on the server Env binding contract.

import type { Env } from '../types';

// Production defaults preserve the existing agent and boss stream polling cadence.
export const DEFAULT_AGENT_STREAM_POLL_INTERVAL_MS = 2_000;
export const DEFAULT_BOSS_STREAM_POLL_INTERVAL_MS = 3_000;

export function getStreamPollIntervalMs(
  env: Pick<Env, 'STREAM_POLL_INTERVAL_MS'>,
  productionDefaultMs: number,
): number {
  const configuredValue = env.STREAM_POLL_INTERVAL_MS?.trim();
  if (!configuredValue) return productionDefaultMs;

  const configuredMs = Number(configuredValue);
  if (!Number.isInteger(configuredMs) || configuredMs <= 0) return productionDefaultMs;
  return configuredMs;
}
