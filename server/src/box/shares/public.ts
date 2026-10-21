// Resolves public capabilities without authentication and applies uniform privacy headers.
// Reuses attachment range streaming while enforcing the public share MIME allowlist.
import { Hono } from 'hono';
import type { Env } from '../../types';
import { serveAttachment } from '../../attachments';
import type { BoxRow, BoxContext } from '../types';
import { tokenHash } from './routes';
import { sharePage } from './page';

const PAGE_CSP = "default-src 'none'; img-src 'self'; media-src 'self'; style-src 'unsafe-inline'; "
  + "base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
const INLINE = new Set(['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/heic',
  'video/mp4', 'video/quicktime']);
type PublicItem = BoxRow & { share_id: string; expires_at: string };
export const publicShares = new Hono<{ Bindings: Env }>();

function missing(c: BoxContext): Response {
  c.header('content-security-policy', PAGE_CSP);
  return c.text('not found', 404);
}

publicShares.use('*', async (c, next) => {
  c.header('content-security-policy', PAGE_CSP);
  await next();
  c.header('cache-control', 'private, no-store');
  c.header('x-robots-tag', 'noindex, nofollow');
  c.header('referrer-policy', 'no-referrer');
  c.header('x-content-type-options', 'nosniff');
  // A request id would make otherwise identical invalid responses distinguishable.
  c.res.headers.delete('x-request-id');
});
publicShares.onError(() => {
  // Do not forward errors containing capability paths to the application logger.
  return new Response('internal server error', { status: 500, headers: {
    'cache-control': 'private, no-store', 'x-robots-tag': 'noindex, nofollow',
    'referrer-policy': 'no-referrer', 'x-content-type-options': 'nosniff',
    'content-security-policy': PAGE_CSP,
  } });
});

async function resolve(c: BoxContext): Promise<PublicItem | null> {
  const token = c.req.param('token') ?? '';
  if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return null;
  return c.env.DB.prepare(`SELECT i.*, s.id AS share_id, s.expires_at FROM box_shares s
    JOIN box_items i ON i.id = s.item_id AND i.boss_id = s.boss_id
    WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ?
    AND i.deleted_at IS NULL`).bind(await tokenHash(token), new Date().toISOString()).first<PublicItem>();
}

publicShares.on(['GET', 'HEAD'], '/:token/file', async c => {
  const item = await resolve(c);
  if (!item?.media_key || item.kind === 'text' || item.kind === 'link') return missing(c);
  const response = await serveAttachment(c.req.raw, c.env.ATTACHMENTS, item.media_key);
  if (response.status === 404) return missing(c);
  const type = (item.media_type ?? 'application/octet-stream').split(';')[0].trim().toLowerCase();
  const disposition = response.headers.get('content-disposition') ?? 'attachment; filename="download"';
  response.headers.set('content-disposition', disposition.replace(/^(inline|attachment)/,
    INLINE.has(type) ? 'inline' : 'attachment'));
  response.headers.set('content-type', INLINE.has(type) ? type : 'application/octet-stream');
  response.headers.set('cache-control', 'private, no-store');
  response.headers.set('content-security-policy', "default-src 'none'; sandbox; frame-ancestors 'none'");
  c.header('content-security-policy', "default-src 'none'; sandbox; frame-ancestors 'none'");
  return response;
});

publicShares.get('/:token', async c => {
  const item = await resolve(c);
  if (!item) return missing(c);
  if (c.req.method === 'GET') {
    await c.env.DB.prepare(`UPDATE box_shares SET view_count = view_count + 1, last_viewed_at = ?
      WHERE id = ?`).bind(new Date().toISOString(), item.share_id).run();
  }
  return c.html(sharePage(item, c.req.param('token'), item.expires_at));
});
publicShares.all('*', c => missing(c));
