// Checks declared multipart sizes before buffering files with the Fetch parser.
// Exports kind limits and parsing with a bounded scan of leading part headers.
import { HTTPException } from 'hono/http-exception';

export const IMAGE_BYTES = 10 * 1024 * 1024;
export const FILE_BYTES = 50 * 1024 * 1024;
const MULTIPART_BYTES = 64 * 1024;

function fileType(prefix: string, boundary: string): string | null {
  for (const part of prefix.split(`--${boundary}`).slice(1)) {
    const end = part.indexOf('\r\n\r\n');
    if (end < 0) continue;
    const headers = part.slice(0, end);
    if (/\r\ncontent-disposition:[^\r\n]*;\s*name=(?:"file"|file)(?:;|\s|$)/i.test(headers)) {
      return /\r\ncontent-type:\s*([^\r\n]+)/i.exec(headers)?.[1].trim().toLowerCase() ?? '';
    }
  }
  return null;
}

function replay(chunks: Uint8Array[], reader: ReadableStreamDefaultReader<Uint8Array>):
  ReadableStream<Uint8Array> {
  let index = 0;
  return new ReadableStream({
    async pull(controller) {
      if (index < chunks.length) {
        controller.enqueue(chunks[index++]);
        return;
      }
      const next = await reader.read();
      if (next.done) controller.close();
      else controller.enqueue(next.value);
    },
    cancel(reason) { return reader.cancel(reason); },
  });
}

export async function multipartForm(request: Request): Promise<FormData> {
  const length = Number(request.headers.get('content-length'));
  if (length > FILE_BYTES + MULTIPART_BYTES) {
    throw new HTTPException(413, { message: 'file too large' });
  }
  if (length <= IMAGE_BYTES + MULTIPART_BYTES || !request.body) return request.formData();
  const contentType = request.headers.get('content-type') ?? '';
  const boundary = /boundary=(?:"([^"]+)"|([^;\s]+))/i.exec(contentType);
  if (!boundary) throw new HTTPException(400, { message: 'missing multipart boundary' });
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  const decoder = new TextDecoder();
  let prefix = '';
  let bytes = 0;
  try {
    while (bytes < MULTIPART_BYTES) {
      const next = await reader.read();
      if (next.done) break;
      chunks.push(next.value);
      const leading = next.value.subarray(0, MULTIPART_BYTES - bytes);
      prefix += decoder.decode(leading, { stream: true });
      bytes += leading.length;
      const type = fileType(prefix, boundary[1] ?? boundary[2]);
      if (type === null) continue;
      if (length > (type.startsWith('image/') ? IMAGE_BYTES : FILE_BYTES) + MULTIPART_BYTES) {
        throw new HTTPException(413, { message: 'file too large' });
      }
      return await new Response(replay(chunks, reader), { headers: request.headers }).formData();
    }
    throw new HTTPException(413, { message: 'multipart headers too large' });
  } catch (error: unknown) {
    await reader.cancel();
    throw error;
  }
}
