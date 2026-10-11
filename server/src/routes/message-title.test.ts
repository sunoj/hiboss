// Verifies the public message contract: bounded titles and preserved Markdown details.
// Exercises send/edit/reply routes against the test Worker and isolated D1.
import { SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase, authHeaders } from '../test-helpers';

beforeAll(seedDatabase);

async function send(body: string, content?: string): Promise<Response> {
  return SELF.fetch('https://test.local/api/messages', {
    method: 'POST', headers: authHeaders(),
    body: JSON.stringify({ body, metadata: content ? { content } : undefined }),
  });
}

describe('Message titles', () => {
  it('rejects 145 characters with a recovery instruction', async () => {
    const response = await send('字'.repeat(145));
    expect(response.status).toBe(400);
    expect(await response.text()).toContain('metadata.content');
  });

  it('accepts 144 Unicode characters and retains the full Markdown content', async () => {
    const title = '🏠'.repeat(144);
    const content = '# Result\n\n**Ready**\n\n- One\n- Two\n\n```swift\nlet ready = true\n```';
    const response = await send(title, content);
    expect(response.status).toBe(201);
    const { id } = await response.json() as { id: string };
    const detail = await SELF.fetch(`https://test.local/api/messages/${id}`, { headers: authHeaders() });
    expect(await detail.json()).toMatchObject({ body: title, metadata: { content } });
  });

  it('rejects an overlong edit without replacing the existing title', async () => {
    const created = await send('Ready');
    const { id } = await created.json() as { id: string };
    const response = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH', headers: authHeaders(), body: JSON.stringify({ body: 'x'.repeat(145) }),
    });
    expect(response.status).toBe(400);
    const detail = await SELF.fetch(`https://test.local/api/messages/${id}`, { headers: authHeaders() });
    expect(await detail.json()).toMatchObject({ body: 'Ready' });
  });

  it('keeps a long boss reply as body text rather than treating it as a title', async () => {
    const created = await send('Ready');
    const { id } = await created.json() as { id: string };
    const text = 'Detailed reply '.repeat(30);
    const reply = await SELF.fetch(`https://test.local/api/messages/${id}/reply`, {
      method: 'POST', headers: authHeaders(), body: JSON.stringify({ body: text }),
    });
    expect(reply.status).toBe(201);
    const detail = await SELF.fetch(`https://test.local/api/messages/${id}`, { headers: authHeaders() });
    const value = await detail.json() as { replies: { body: string }[] };
    expect(value.replies[0].body).toBe(text.trim());
  });
});
