// Validates updates to app delivery destinations.
// Exports request parsers; depends only on destination contracts and priority constants.
import { PRIORITY_RANK } from './types';
import type { Priority } from '../types';

export type DestinationPatch = { enabled?: boolean; min_priority?: Priority; honours_quiet_hours?: boolean; label?: string };
export function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null;
}
function label(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= 100 && !/[\x00-\x1f]/.test(value);
}
export function parseDestinationPatch(value: unknown): DestinationPatch | null {
  const body = record(value);
  if (!body || !Object.keys(body).length) return null;
  if (Object.keys(body).some(key => !['enabled', 'min_priority', 'honours_quiet_hours', 'label'].includes(key))) return null;
  if ('enabled' in body && typeof body.enabled !== 'boolean') return null;
  if ('honours_quiet_hours' in body && typeof body.honours_quiet_hours !== 'boolean') return null;
  if ('min_priority' in body && (typeof body.min_priority !== 'string' || !Object.hasOwn(PRIORITY_RANK, body.min_priority))) return null;
  if ('label' in body && !label(body.label)) return null;
  return body as DestinationPatch;
}
