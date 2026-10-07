// Serves Box media only after resolving the caller's access to its item.
// Reuses attachment range handling and disables caching of private bytes.
import { serveAttachment } from '../attachments';
import { findItem } from './store';
import type { BoxContext } from './types';

export async function boxMedia(c: BoxContext): Promise<Response> {
  const item = await findItem(c, c.req.param('id') ?? '');
  if (!item?.media_key) return c.text('not found', 404);
  const response = await serveAttachment(c.req.raw, c.env.ATTACHMENTS, item.media_key);
  response.headers.set('cache-control', 'private, no-store');
  return response;
}
