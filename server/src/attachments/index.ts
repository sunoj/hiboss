// Serves immutable media attachments with streaming byte ranges and HEAD metadata.
// Exports serveAttachment for the attachment HTTP router.
// Dependencies: injected R2 binding, HTTP Request/Response, and the range parser.

import type { Env } from '../types';
import { parseByteRange } from './range';

type AttachmentBucket = Env['ATTACHMENTS'];
type AttachmentObject = NonNullable<Awaited<ReturnType<AttachmentBucket['head']>>>;
const IMMUTABLE_CACHE = 'public, max-age=31536000, immutable';
const INLINE_TYPES = new Set(['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/avif', 'video/mp4']);

export async function serveAttachment(
  request: Request,
  bucket: AttachmentBucket,
  key: string,
): Promise<Response> {
  if (request.method === 'HEAD') {
    const object = await bucket.head(key);
    return object ? new Response(null, { headers: attachmentHeaders(object) }) : missingAttachment();
  }
  const rangeHeader = request.headers.get('range');
  if (!rangeHeader) return fullAttachment(bucket, key);
  const metadata = await bucket.head(key);
  if (!metadata) return missingAttachment();
  const validator = request.headers.get('if-range');
  if (validator !== null && validator !== metadata.httpEtag) return fullAttachment(bucket, key);
  const range = parseByteRange(rangeHeader, metadata.size);
  if (range.kind === 'full') return fullAttachment(bucket, key);
  if (range.kind === 'unsatisfiable') {
    return new Response(null, {
      status: 416,
      headers: { 'Content-Range': `bytes */${metadata.size}`, 'Accept-Ranges': 'bytes' },
    });
  }
  const object = await bucket.get(key, { range: { offset: range.offset, length: range.length } });
  if (!object) return missingAttachment();
  const headers = attachmentHeaders(object);
  headers.set('content-length', String(range.length));
  headers.set('content-range', `bytes ${range.offset}-${range.offset + range.length - 1}/${object.size}`);
  return new Response(object.body as ReadableStream, { status: 206, headers });
}

async function fullAttachment(bucket: AttachmentBucket, key: string): Promise<Response> {
  const object = await bucket.get(key);
  if (!object) return missingAttachment();
  return new Response(object.body as ReadableStream, { headers: attachmentHeaders(object) });
}

function attachmentHeaders(object: AttachmentObject): Headers {
  const contentType = (object.httpMetadata?.contentType ?? '').split(';', 1)[0].trim().toLowerCase();
  const inline = INLINE_TYPES.has(contentType);
  const headers = new Headers({
    'content-type': inline ? contentType : 'application/octet-stream',
    'content-length': String(object.size),
    'accept-ranges': 'bytes',
    etag: object.httpEtag,
    'cache-control': inline ? IMMUTABLE_CACHE : 'no-store',
    'x-content-type-options': 'nosniff',
    'content-security-policy': "sandbox; default-src 'none'; img-src 'self' data:; media-src 'self'; base-uri 'none'; form-action 'none'",
  });
  // Encode metadata at download time so legacy objects receive the same protection.
  const filename = (object.customMetadata?.filename || 'download').replace(/[\u0000-\u001f\u007f-\u009f]/g, '_');
  const fallback = filename.replace(/[^\x20-\x7e]|["\\]/g, '_');
  const encoded = encodeURIComponent(filename).replace(/['()*]/g, char => `%${char.charCodeAt(0).toString(16).toUpperCase()}`);
  headers.set('content-disposition', `${inline ? 'inline' : 'attachment'}; filename="${fallback}"; filename*=UTF-8''${encoded}`);
  return headers;
}

function missingAttachment(): Response {
  return new Response('not found', { status: 404 });
}
