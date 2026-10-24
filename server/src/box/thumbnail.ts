// Validates and serves client-generated Box thumbnails without decoding images.
// Exports thumbnail type, size and magic checks and the PUT/GET/HEAD route handlers.
import { HTTPException } from 'hono/http-exception';
import { canEditItem } from './access';
import { THUMB_BYTES } from './multipart';
import { findItem, storeThumbnail } from './store';
import { itemResponse, type BoxContext, type BoxRow, type BoxThumbnail } from './types';

const MAGIC: Record<string, (bytes: Uint8Array) => boolean> = {
  'image/jpeg': bytes => starts(bytes, [0xff, 0xd8, 0xff]),
  'image/png': bytes => starts(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  'image/webp': bytes => starts(bytes, [0x52, 0x49, 0x46, 0x46])
    && starts(bytes.subarray(8), [0x57, 0x45, 0x42, 0x50]),
};

function starts(bytes: Uint8Array, prefix: number[]): boolean {
  return bytes.length >= prefix.length && prefix.every((byte, index) => bytes[index] === byte);
}

export function acceptsThumbnail(kind: string, hasMedia: boolean): boolean {
  return hasMedia && (kind === 'image' || kind === 'video');
}

export function checkThumbnail(declared: string, bytes: Uint8Array): BoxThumbnail {
  const type = declared.split(';')[0].trim().toLowerCase();
  const magic = MAGIC[type];
  if (!magic) throw new HTTPException(415, { message: 'thumbnail must be image/jpeg, image/png or image/webp' });
  if (bytes.length > THUMB_BYTES) throw new HTTPException(413, { message: 'thumbnail exceeds 256 KiB' });
  if (!magic(bytes)) throw new HTTPException(415, { message: 'thumbnail bytes do not match its type' });
  return { type, bytes };
}

async function editableMedia(c: BoxContext): Promise<BoxRow> {
  const row = await findItem(c, c.req.param('id') ?? '');
  if (!row || !canEditItem(c, row)) throw new HTTPException(404, { message: 'not found' });
  if (!acceptsThumbnail(row.kind, row.media_key !== null)) {
    throw new HTTPException(409, { message: 'only image and video items accept a thumbnail' });
  }
  return row;
}

export async function putThumbnail(c: BoxContext): Promise<Response> {
  const row = await editableMedia(c);
  if (Number(c.req.header('content-length')) > THUMB_BYTES) {
    throw new HTTPException(413, { message: 'thumbnail exceeds 256 KiB' });
  }
  const bytes = new Uint8Array(await c.req.arrayBuffer());
  const thumbnail = checkThumbnail(c.req.header('content-type') ?? '', bytes);
  const updated = await storeThumbnail(c, row, thumbnail);
  return updated ? c.json(itemResponse(updated)) : c.text('not found', 404);
}

export async function getThumbnail(c: BoxContext): Promise<Response> {
  const row = await findItem(c, c.req.param('id') ?? '');
  if (!row?.thumb_key) return c.text('not found', 404);
  const head = c.req.method === 'HEAD';
  const object = head ? await c.env.ATTACHMENTS.head(row.thumb_key)
    : await c.env.ATTACHMENTS.get(row.thumb_key);
  if (!object) return c.text('not found', 404);
  const headers = new Headers({
    'content-type': object.httpMetadata?.contentType ?? 'application/octet-stream',
    'content-length': String(object.size), 'x-content-type-options': 'nosniff',
    'cache-control': 'private, max-age=86400', etag: object.httpEtag,
  });
  if (c.req.header('if-none-match') === object.httpEtag) {
    headers.delete('content-length');
    return new Response(null, { status: 304, headers });
  }
  const body = !head && 'body' in object ? object.body as ReadableStream : null;
  return new Response(body, { headers });
}
