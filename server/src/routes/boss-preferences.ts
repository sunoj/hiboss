// Validates retained boss preferences and rejects removed notification settings.
// Exports validatePreferences; depends only on typed JSON records.
export function validatePreferences(prefs: Record<string, unknown>): string | null {
  if ('preferred_channel' in prefs || 'notify_priorities' in prefs) return 'use destination notification settings';
  if ('quiet_hours' in prefs && prefs.quiet_hours !== null) {
    const qh = prefs.quiet_hours as Record<string, unknown>;
    if (typeof qh !== 'object' || typeof qh.start !== 'string' || typeof qh.end !== 'string') {
      return 'quiet_hours must have start and end time strings (HH:MM)';
    }
  }
  return null;
}
