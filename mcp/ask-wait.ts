// Keeps an MCP ask open for its whole lifetime: clamps the requested timeout to the server's
// ask range and polls in bounded windows until a reply arrives or the deadline passes.
// Exports askTimeoutSeconds and waitForReply; the caller supplies the poll transport.

/** The server's ask lifetime range; the boss always gets at least a minute to answer. */
export const MIN_ASK_SECONDS = 60;
export const MAX_ASK_SECONDS = 86_400;
/** The server caps one poll request at five minutes. */
export const MAX_POLL_WINDOW_SECONDS = 300;
const DEFAULT_ASK_SECONDS = 1800;

export function askTimeoutSeconds(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return DEFAULT_ASK_SECONDS;
  return Math.min(MAX_ASK_SECONDS, Math.max(MIN_ASK_SECONDS, Math.trunc(value)));
}

export type PollWindow<T> = (windowSeconds: number) => Promise<T>;

/** Polls until `hasReply` holds or `timeoutSeconds` elapse; returns the last poll result. */
export async function waitForReply<T>(
  poll: PollWindow<T>,
  hasReply: (result: T) => boolean,
  timeoutSeconds: number,
  now: () => number = Date.now,
): Promise<T> {
  const deadline = now() + timeoutSeconds * 1000;
  let result = await poll(windowFor(deadline - now()));
  while (!hasReply(result) && now() < deadline) {
    result = await poll(windowFor(deadline - now()));
  }
  return result;
}

function windowFor(remainingMs: number): number {
  return Math.min(MAX_POLL_WINDOW_SECONDS, Math.max(1, Math.ceil(remainingMs / 1000)));
}
