// Message API regression suites extracted to keep each file bounded.
// Registers cases in messages.test.ts; depends on its shared database setup.
import { env, SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { authHeaders } from '../../test-helpers';

describe('POST /api/messages with metadata', () => {
  it('stores file_url in metadata', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'See file', file_url: 'https://example.com/img.png' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    // Verify metadata contains file_url
    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { metadata: Record<string, unknown> | null };
    expect(msg.metadata?.['file_url']).toBe('https://example.com/img.png');
  });

  it('stores custom metadata', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'With meta', metadata: { task: 'test-123' } }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { metadata: Record<string, unknown> | null };
    expect(msg.metadata?.['task']).toBe('test-123');
  });

  it('accepts option arrays and preserves commas inside an option', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Choose one', options: ['A, recommended', 'B'] }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };
    const row = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?')
      .bind(id).first<{ metadata: string }>();
    expect(JSON.parse(row?.metadata ?? '{}').options).toEqual(['A, recommended', 'B']);
  });

  it('rejects string options and arrays with more than five choices', async () => {
    const stringResult = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Choose one', options: 'A,B' }),
    });
    const overflowResult = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Choose one', options: ['1', '2', '3', '4', '5', '6'] }),
    });

    expect(stringResult.status).toBe(400);
    expect(overflowResult.status).toBe(400);
  });

  it('rejects option_media with a label that is not an offered option', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({
        body: 'Choose one',
        options: ['A', 'B'],
        metadata: { option_media: [{ label: 'C', url: 'https://files.test/c.png' }] },
      }),
    });

    expect(res.status).toBe(400);
    expect(await res.text()).toContain('not an option');
  });
});

describe('POST /api/messages with type', () => {
  it('stores message type', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Deploy done', type: 'task_update' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { type: string | null };
    expect(msg.type).toBe('task_update');
  });

  it('defaults type to text', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Plain message' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { type: string | null };
    expect(msg.type).toBe('text');
  });
});

describe('POST /api/messages/:id/poll', () => {
  it('returns 400 for non-blocking message', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Async msg', mode: 'async' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}/poll`, {
      method: 'POST',
      headers: authHeaders(),
    });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown message', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/nonexistent/poll', {
      method: 'POST',
      headers: authHeaders(),
    });
    expect(res.status).toBe(404);
  });
});
