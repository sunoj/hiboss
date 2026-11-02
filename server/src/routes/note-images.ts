// Validate note image uploads and serve objects after session authorization.
// Shared by boss and agent note routes; uses D1 metadata and private R2 objects.
import type { Context } from 'hono';
import type { Env } from '../types';
import { HTTPException } from 'hono/http-exception';

export interface NoteImage { index: number; content_type: string; bytes: number }
export interface UploadImage { content_type: string; data: ArrayBuffer }

function matches(type: string, data: Uint8Array): boolean {
  const text = (start: number, end: number) => String.fromCharCode(...data.slice(start, end));
  switch (type) {
    case 'image/jpeg': return data[0] === 255 && data[1] === 216 && data[2] === 255;
    case 'image/png': return [137, 80, 78, 71, 13, 10, 26, 10].every((v, i) => data[i] === v);
    case 'image/gif': return ['GIF87a', 'GIF89a'].includes(text(0, 6));
    case 'image/webp': return text(0, 4) === 'RIFF' && text(8, 12) === 'WEBP';
    case 'image/heic': {
      const size = new DataView(data.buffer, data.byteOffset, data.byteLength);
      if (data.length < 16 || text(4, 8) !== 'ftyp') return false;
      const end = size.getUint32(0);
      if (end < 16 || end > data.length || end % 4 !== 0) return false;
      const brands = [text(8, 12)];
      for (let i = 16; i < end; i += 4) brands.push(text(i, i + 4));
      return brands.some(b => ['heic', 'heix', 'hevc', 'hevx'].includes(b));
    }
    default: return false;
  }
}

export async function notePayload(c: Context<{ Bindings: Env }>):
Promise<{ body: string; images: UploadImage[] }> {
  let body: unknown;
  let files: FormDataEntryValue[] = [];
  try {
    if (c.req.header('content-type')?.includes('multipart/form-data')) {
      const form = await c.req.formData();
      body = form.get('body');
      files = form.getAll('image');
    } else {
      body = (await c.req.json<{ body?: unknown }>())?.body;
    }
  } catch { throw new HTTPException(400, { message: 'invalid note payload' }); }
  const text = typeof body === 'string' ? body.trim() : '';
  if (files.length > 4 || [...text].length > 4000 || (!text && !files.length)) {
    throw new HTTPException(400, { message: 'body or 1..4 images required; body max 4000 characters' });
  }
  const images: UploadImage[] = [];
  for (const file of files) {
    if (!(file instanceof File)) throw new HTTPException(400, { message: 'image must be a file' });
    if (file.size > 10 * 1024 * 1024) throw new HTTPException(413, { message: 'image exceeds 10 MB' });
    const data = await file.arrayBuffer();
    if (!matches(file.type, new Uint8Array(data))) {
      throw new HTTPException(400, { message: 'unsupported or mismatched image type' });
    }
    images.push({ content_type: file.type, data });
  }
  return { body: text, images };
}

export async function withImages<T extends { id: string }>(env: Env, note: T):
Promise<T & { images: NoteImage[] }> {
  const images = await env.DB.prepare(`SELECT idx AS "index", content_type, bytes
    FROM session_note_images WHERE note_id = ? ORDER BY idx`).bind(note.id).all<NoteImage>();
  return { ...note, images: images.results };
}

export async function noteImage(c: Context<{ Bindings: Env }>): Promise<Response> {
  const index = c.req.param('index');
  if (!/^[0-3]$/.test(index)) return c.text('not found', 404);
  const image = await c.env.DB.prepare(`SELECT i.r2_key, i.content_type FROM session_note_images i
    JOIN session_notes n ON n.id = i.note_id WHERE n.session_id = ? AND n.id = ? AND i.idx = ?`)
    .bind(c.req.param('id'), c.req.param('noteId'), Number(index))
    .first<{ r2_key: string; content_type: string }>();
  if (!image) return c.text('not found', 404);
  const object = await c.env.ATTACHMENTS.get(image.r2_key);
  if (!object) return c.text('not found', 404);
  return new Response(object.body, { headers: {
    'Content-Type': image.content_type, 'Cache-Control': 'private, max-age=3600',
  } });
}
