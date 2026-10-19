// Validates collection names in JSON create and rename requests.
// Exports the trimmed name with Unicode character and control checks.
import { HTTPException } from 'hono/http-exception';
import type { BoxContext } from '../types';

export async function collectionName(c: BoxContext): Promise<string> {
  let body: unknown;
  try {
    body = await c.req.json<unknown>();
  } catch {
    throw new HTTPException(400, { message: 'invalid JSON' });
  }
  if (!body || typeof body !== 'object' || !('name' in body) || typeof body.name !== 'string') {
    throw new HTTPException(400, { message: 'name is required' });
  }
  const name = body.name.trim();
  if (!name || [...name].length > 64 || /\p{Cc}/u.test(body.name)) {
    throw new HTTPException(400, { message: 'name must have 1–64 characters and no controls' });
  }
  return name;
}
