// Channel-name validation shared by every write that configures a channel.
// Exports channelWriteError; email is refused by name because it has no delivery adapter.

/** Returns the 400 message for a channel value a write must refuse, or null when allowed. */
export function channelWriteError(value: unknown, allowed: readonly string[], invalid: string): string | null {
  if (value === 'email') return 'email is not a supported channel';
  return typeof value === 'string' && allowed.includes(value) ? null : invalid;
}
