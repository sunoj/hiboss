// Revalidate credentials and resource access before releasing each SSE chunk.
import type { Context } from 'hono';
import type { Env } from '../types';
import { createAuthValidator } from './auth';

export function authorizedStreamWriter(
  c: Context<{ Bindings: Env }>,
  writable: WritableStream,
  hasAccess: () => Promise<boolean> = async () => true,
): WritableStreamDefaultWriter {
  const validCredential = createAuthValidator(c);
  const writer = writable.getWriter();
  return new WritableStream({
    async write(chunk) {
      try {
        if (!await validCredential() || !await hasAccess()) throw new Error('stream access revoked');
      } catch (error) {
        // Finish the HTTP body without sending the chunk or advancing delivery state.
        await writer.close();
        throw error;
      }
      await writer.write(chunk);
    },
    close: () => writer.close(),
    abort: reason => writer.abort(reason),
  }).getWriter();
}
