// Validates Box JSON and multipart metadata without fetching supplied URLs.
// Exports ingestion and patch parsing with byte-based text and media limits.
import { HTTPException } from 'hono/http-exception';
import { multipartForm, IMAGE_BYTES, FILE_BYTES } from './multipart';
import { SOURCES, type BoxContext, type BoxMetadata, type BoxUpload } from './types';

const TEXT_BYTES = 16 * 1024;

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new HTTPException(400, { message: 'metadata must be an object' });
  }
  return value as Record<string, unknown>;
}

function optionalText(value: unknown, field: string): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw new HTTPException(400, { message: `${field} must be text` });
  if ((field === 'text' || field === 'note') && new TextEncoder().encode(value).length > TEXT_BYTES) {
    throw new HTTPException(413, { message: `${field} exceeds 16 KB` });
  }
  if ((field === 'url' && new TextEncoder().encode(value).length > 8 * 1024)
    || (field === 'project' && value.length > 128)) {
    throw new HTTPException(400, { message: `${field} too long` });
  }
  return value;
}

function tags(value: unknown): string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || !value.every(tag => typeof tag === 'string')) {
    throw new HTTPException(400, { message: 'tags must be an array of strings' });
  }
  if (value.length > 20 || value.some(tag => tag.length > 64)) {
    throw new HTTPException(400, { message: 'tags exceed 20 entries or 64 characters' });
  }
  return value as string[];
}

function measurement(value: unknown, field: string): number | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    throw new HTTPException(400, { message: `${field} must be a nonnegative integer` });
  }
  return value;
}

function metadata(value: unknown): BoxMetadata {
  const body = record(value);
  const source = body.source ?? 'cli';
  if (!SOURCES.some(candidate => candidate === source)) {
    throw new HTTPException(400, { message: 'invalid source' });
  }
  return {
    text: optionalText(body.text, 'text'), url: optionalText(body.url, 'url'),
    note: optionalText(body.note, 'note'), project: optionalText(body.project, 'project'),
    tags: tags(body.tags), source: source as BoxMetadata['source'],
    width: measurement(body.width, 'width'), height: measurement(body.height, 'height'),
    duration_ms: measurement(body.duration_ms, 'duration_ms'),
  };
}

async function parseBody(c: BoxContext): Promise<{ value: unknown; file: File | null }> {
  try {
    if (!(c.req.header('content-type') ?? '').includes('multipart/form-data')) {
      return { value: await c.req.json<unknown>(), file: null };
    }
    const form = await multipartForm(c.req.raw);
    const file = form.get('file');
    const meta = form.get('meta');
    if (!(file instanceof File) || typeof meta !== 'string') {
      throw new HTTPException(400, { message: 'meta and file fields are required' });
    }
    return { value: JSON.parse(meta) as unknown, file };
  } catch (error: unknown) {
    if (error instanceof HTTPException) throw error;
    throw new HTTPException(400, { message: 'invalid JSON or multipart body' });
  }
}

export async function parseUpload(c: BoxContext): Promise<BoxUpload> {
  const { value, file } = await parseBody(c);
  const meta = metadata(value);
  if (!file) {
    if (!meta.url && !meta.text) throw new HTTPException(400, { message: 'url or text is required' });
    return { meta, file, kind: meta.url ? 'link' : 'text' };
  }
  const kind = file.type.startsWith('image/') ? 'image' : file.type.startsWith('video/') ? 'video' : 'file';
  if (file.size > (kind === 'image' ? IMAGE_BYTES : FILE_BYTES)) {
    throw new HTTPException(413, { message: 'file too large' });
  }
  if (!file.size) throw new HTTPException(400, { message: 'empty file' });
  return { meta, file, kind };
}

export async function parsePatch(c: BoxContext):
  Promise<Partial<Pick<BoxMetadata, 'note' | 'tags' | 'project'>>> {
  let value: unknown;
  try { value = await c.req.json<unknown>(); }
  catch { throw new HTTPException(400, { message: 'invalid JSON body' }); }
  const body = record(value);
  if (Object.keys(body).some(key => !['note', 'tags', 'project'].includes(key))) {
    throw new HTTPException(400, { message: 'only note, tags and project can be edited' });
  }
  return {
    ...('note' in body ? { note: optionalText(body.note, 'note') } : {}),
    ...('project' in body ? { project: optionalText(body.project, 'project') } : {}),
    ...('tags' in body ? { tags: tags(body.tags) } : {}),
  };
}
