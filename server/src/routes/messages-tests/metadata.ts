// Message API regression suites extracted to keep each file bounded.
// Registers cases in messages.test.ts; depends on its shared database setup.
import { env, SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { seedBossToken, authHeaders } from '../../test-helpers';

describe('POST /api/messages with metadata', () => {
  it('normalizes partial descriptions and preserves them in boss serialization', async () => {
    const descriptions = [{ label: ' B ', text: ' **Keep=current** ' }];
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST', headers: authHeaders(),
      body: JSON.stringify({ body: 'Choose', options: ['A', 'B'],
        metadata: { option_descriptions: descriptions } }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };
    await seedBossToken('Descriptions', 'admin', 'description-boss-token', 'description-boss');
    const response = await SELF.fetch(`https://test.local/api/boss/messages/${id}`, {
      headers: { Authorization: 'Bearer description-boss-token' },
    });
    expect(response.status).toBe(200);
    const message = await response.json() as { metadata: Record<string, unknown> };
    expect(message.metadata.option_descriptions)
      .toEqual([{ label: 'B', text: '**Keep=current**' }]);
  });

  it.each([
    [undefined, [{ label: 'A', text: 'text' }], 'requires options'],
    [['A'], [], '1 to'],
    [['A'], null, '1 to'],
    [['A'], {}, '1 to'],
    [['A'], [{ label: 'A', text: 'x' }, { label: 'A', text: 'y' }], '1 to'],
    [['A', 'B'], [{ label: 'A', text: 'x' }, { label: ' A ', text: 'y' }], 'unique'],
    [['A'], [null], 'object'],
    [['A'], [[]], 'object'],
    [['A'], [{ label: 'B', text: 'text' }], 'match an option'],
    [['A'], [{ label: 1, text: 'text' }], 'match an option'],
    [['A'], [{ label: 'A', text: ' ' }], '1 to 200'],
    [['A'], [{ label: 'A', text: 1 }], '1 to 200'],
    [['A'], [{ label: 'A', text: 'x'.repeat(201) }], '1 to 200'],
  ])('rejects invalid descriptions (%#)', async (options, descriptions, error) => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST', headers: authHeaders(),
      body: JSON.stringify({ body: 'Choose', options,
        metadata: { option_descriptions: descriptions } }),
    });
    expect(res.status).toBe(400);
    expect(await res.text()).toContain(error as string);
  });

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

  it('strips malformed answered_by before storing agent message history', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({
        body: 'History should remain decodable',
        metadata: { answered_by: { client_id: 'forged' }, task: 'keep' },
      }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };
    const stored = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?')
      .bind(id).first<{ metadata: string }>();
    const storedMetadata = JSON.parse(stored?.metadata ?? '{}') as Record<string, unknown>;
    expect(storedMetadata['task']).toBe('keep');
    expect(storedMetadata['answered_by']).toBeUndefined();

    const history = await SELF.fetch('https://test.local/api/messages?direction=all&limit=100', {
      headers: authHeaders(),
    });
    const page = await history.json() as {
      messages: { id: string; metadata: Record<string, unknown> | null }[];
    };
    expect(page.messages.find(message => message.id === id)?.metadata?.['answered_by']).toBeUndefined();
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
