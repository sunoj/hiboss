// Real Worker coverage for note-linked sends, authorization, replay and signing.
// Uses shared D1 seeds and signing helpers without replacing the send pipeline.
import { beforeAll, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { seedDatabase, seedBossToken } from './test-helpers';
import {
  enrollment, messagePayload, newSigner, request, seedAgent, signedMessage,
  type TestAgent,
} from './message-security/agent-signing-test-support';

let agent: TestAgent;
let other: TestAgent;
const session = 'reply-session';
const boss = 'reply-boss';
type Reply = { message_id: string; body: string; agent_name: string; created_at: string };
type Note = { id: string; status: string; read_at: string | null; replies: Reply[] };

beforeAll(async () => {
  await seedDatabase();
  agent = await seedAgent('note-replier');
  other = await seedAgent('other-replier');
  await seedBossToken('Reply boss', 'admin', boss);
  for (const [id, owner] of [[session, agent.id], ['reply-second', agent.id], ['reply-foreign', other.id]]) {
    await env.DB.prepare('INSERT INTO sessions (id, agent_id) VALUES (?, ?)').bind(id, owner).run();
  }
});

async function note(id = session): Promise<Note> {
  const response = await request(`/boss/sessions/${id}/notes`, boss, 'POST', { body: 'Please respond' });
  expect(response.status).toBe(201);
  const created = await response.json<Note>();
  expect(created.replies).toEqual([]);
  return created;
}

const send = (id: unknown, overrides: Record<string, unknown> = {}, token?: string) =>
  request('/messages', token ?? agent.token, 'POST', {
    body: 'Reply title', session_id: session, metadata: { note_id: id }, ...overrides,
  });
const counts = async () => ({
  messages: await env.DB.prepare('SELECT COUNT(*) AS n FROM messages').first(),
  links: await env.DB.prepare('SELECT COUNT(*) AS n FROM session_note_replies').first(),
});

it('rejects notes in another session or owned by another agent without inserting anything', async () => {
  const second = await note('reply-second');
  const foreign = await note('reply-foreign');
  const before = await counts();
  for (const id of [second.id, foreign.id, 'missing']) {
    const response = await send(id);
    expect(response.status).toBe(400);
    expect(await response.text()).toContain('note does not belong');
  }
  expect((await send(foreign.id, { session_id: 'reply-foreign' })).status).toBe(400);
  expect(await counts()).toEqual(before);
});

it('rejects peer targets, asks, missing sessions and non-text replies before insertion', async () => {
  const created = await note();
  const before = await counts();
  for (const overrides of [
    { to: 'other-replier' }, { options: ['Yes', 'No'] }, { mode: 'blocking' },
    { session_id: null }, { file_url: 'https://example.com/image.png' }, { type: 'image' },
  ]) {
    expect((await send(created.id, overrides)).status).toBe(400);
  }
  for (const id of [42, '', null]) expect((await send(id)).status).toBe(400);
  expect(await counts()).toEqual(before);
  expect(await env.DB.prepare('SELECT status, read_at FROM session_notes WHERE id = ?')
    .bind(created.id).first()).toEqual({ status: 'pending', read_at: null });
});

it('retries one message and link, marks read once, and returns ordered displayable replies', async () => {
  const created = await note();
  const first = await send(created.id, { idempotency_key: 'note-reply-retry' });
  expect(first.status).toBe(201);
  const receipt = await first.json<{ id: string }>();
  const retry = await send(created.id, { idempotency_key: 'note-reply-retry' });
  expect(retry.status).toBe(200);
  expect((await retry.json<{ id: string }>()).id).toBe(receipt.id);
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM session_note_replies WHERE note_id = ?')
    .bind(created.id).first()).toEqual({ n: 1 });
  const state = await env.DB.prepare('SELECT status, read_at FROM session_notes WHERE id = ?')
    .bind(created.id).first<{ status: string; read_at: string }>();
  expect(state?.status).toBe('read');
  expect(state?.read_at).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
  await env.DB.prepare("UPDATE session_notes SET read_at = '2000-01-01 00:00:00' WHERE id = ?")
    .bind(created.id).run();
  const second = await send(created.id, {
    metadata: { note_id: created.id, content: 'Full\nMarkdown text' },
  });
  expect(second.status).toBe(201);
  const secondId = (await second.json<{ id: string }>()).id;
  for (const [path, token] of [
    [`/sessions/${session}/notes?status=all`, agent.token], [`/boss/sessions/${session}/notes`, boss],
  ]) {
    const listing = await (await request(path, token)).json<{ notes: Note[] }>();
    const returned = listing.notes.find(n => n.id === created.id);
    expect(returned?.read_at).toBe('2000-01-01 00:00:00');
    expect(returned?.replies).toEqual([
      { message_id: receipt.id, body: 'Reply title', agent_name: 'note-replier',
        created_at: expect.any(String) },
      { message_id: secondId, body: 'Full\nMarkdown text', agent_name: 'note-replier',
        created_at: expect.any(String) },
    ]);
  }
  const pending = await (await request(`/sessions/${session}/notes`, agent.token)).json<{ notes: Note[] }>();
  expect(pending.notes.some(n => n.id === created.id)).toBe(false);
});

it('keeps signing required and authenticates note_id while deduplicating signed retries', async () => {
  const signer = await newSigner();
  expect((await request('/agents/me/signing-keys', agent.token, 'POST',
    await enrollment(agent, signer))).status).toBe(201);
  const created = await note();
  const metadata = { note_id: created.id };
  const signed = await signedMessage(signer, messagePayload(agent.id, {
    body: 'Reply title', session_id: session, metadata,
  }));
  expect((await send(created.id)).status).toBe(401);
  const another = await note();
  expect((await send(another.id, { signed_message: signed })).status).toBe(401);
  const before = await counts();
  const responses = await Promise.all([1, 2].map(() => send(created.id, { signed_message: signed })));
  expect(responses.map(r => r.status).sort()).toEqual([200, 201]);
  const receipts = await Promise.all(responses.map(r => r.json<{ id: string }>()));
  expect(receipts[0].id).toBe(receipts[1].id);
  const after = await counts();
  expect(after.messages).toEqual({ n: (before.messages as { n: number }).n + 1 });
  expect(after.links).toEqual({ n: (before.links as { n: number }).n + 1 });
  const stored = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?')
    .bind(receipts[0].id).first<{ metadata: string }>();
  expect(JSON.parse(stored?.metadata ?? '{}')).toMatchObject({ note_id: created.id,
    provenance: { signature: { signed_message: signed } } });
});
