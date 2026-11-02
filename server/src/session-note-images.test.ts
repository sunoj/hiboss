// Image note integration coverage through the real Worker, D1 and R2.
// Tests authorization boundaries, image validation, retries and atomic persistence.
import { beforeAll, expect, it } from 'vitest';
import { env, SELF } from 'cloudflare:test';
import { seedDatabase, seedBossToken, authHeaders, createAgentAuth } from './test-helpers';

const png = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
const base = '/api/boss/sessions/image-session/notes';
const headers = (token = 'images-manager') => ({ Authorization: `Bearer ${token}` });
type Note = { id: string; body: string; images: { index: number; content_type: string; bytes: number }[] };
function upload(files = [new File([png], 'image.png', { type: 'image/png' })],
  token = 'images-manager', key?: string, body = '') {
  const form = new FormData();
  form.set('body', body);
  files.forEach(file => form.append('image', file));
  return SELF.fetch(`https://test${base}`, {
    method: 'POST', headers: { ...headers(token), ...(key ? { 'Idempotency-Key': key } : {}) }, body: form,
  });
}
const get = (path: string, token = 'images-manager') =>
  SELF.fetch(`https://test${path}`, { headers: headers(token) });
const imagePath = (note: Note) => `${base}/${note.id}/images/0`;

beforeAll(async () => {
  await seedDatabase();
  for (const [role, token] of [['manager', 'images-manager'], ['viewer', 'images-viewer']] as const) {
    const boss = await seedBossToken(role, role, token);
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(boss, 'test-agent-id').run();
  }
  await seedBossToken('No access', 'manager', 'images-denied');
  await createAgentAuth('image-other-agent', 'image-other-key');
  for (const id of ['image-session', 'image-second-session']) {
    await env.DB.prepare("INSERT INTO sessions (id, agent_id, status) VALUES (?, ?, 'working')")
      .bind(id, 'test-agent-id').run();
  }
});

it('creates image-only notes, returns ordered metadata and serves private bytes to readers', async () => {
  const response = await upload();
  expect(response.status).toBe(201);
  const note = await response.json<Note>();
  expect(note.body).toBe('');
  expect(note.images).toEqual([{ index: 0, content_type: 'image/png', bytes: png.length }]);
  for (const token of ['images-manager', 'images-viewer']) {
    const image = await get(imagePath(note), token);
    expect(image.status).toBe(200);
    expect(image.headers.get('content-type')).toBe('image/png');
    expect(image.headers.get('cache-control')).toBe('private, max-age=3600');
    expect(new Uint8Array(await image.arrayBuffer())).toEqual(png);
  }
  const agent = await SELF.fetch(`https://test/api/sessions/image-session/notes/${note.id}/images/0`,
    { headers: authHeaders() });
  expect(agent.status).toBe(200);
  expect(new Uint8Array(await agent.arrayBuffer())).toEqual(png);
  const history = await (await get(base)).json<{ notes: Note[] }>();
  expect(history.notes.find(n => n.id === note.id)?.images).toEqual(note.images);
});

it('rejects bosses without access, wrong note/session pairing, foreign agents and viewer writes', async () => {
  const note = await (await upload()).json<Note>();
  expect((await get(imagePath(note), 'images-denied')).status).toBe(404);
  const wrongSession = imagePath(note).replace('image-session', 'image-second-session');
  expect((await get(wrongSession)).status).toBe(404);
  const path = `/api/sessions/image-session/notes/${note.id}/images/0`;
  expect((await get(path, 'image-other-key')).status).toBe(404);
  expect((await SELF.fetch(`https://test${path.replace('image-session', 'image-second-session')}`,
    { headers: authHeaders() })).status).toBe(404);
  for (const index of ['1', '4', '-1', '0x0', '00']) {
    expect((await get(`${base}/${note.id}/images/${index}`)).status).toBe(404);
  }
  expect((await upload(undefined, 'images-viewer')).status).toBe(403);
});

it('rejects spoofed types, unsupported images, excessive size/count and empty notes', async () => {
  const file = (bytes: Uint8Array<ArrayBuffer>, type: string) => new File([bytes], 'image', { type });
  expect((await upload([file(new Uint8Array([1, 2, 3]), 'image/png')])).status).toBe(400);
  expect((await upload([file(png, 'image/jpeg')])).status).toBe(400);
  expect((await upload([file(png, 'image/svg+xml')])).status).toBe(400);
  expect((await upload([file(new Uint8Array(10 * 1024 * 1024 + 1), 'image/png')])).status).toBe(413);
  expect((await upload(Array(5).fill(file(png, 'image/png')))).status).toBe(400);
  expect((await upload([])).status).toBe(400);
  const text = await (await upload([], undefined, undefined, 'text only')).json<Note>();
  expect(text.images).toEqual([]);
});

it('accepts all five declared signatures and preserves image order', async () => {
  const signatures: [string, Uint8Array<ArrayBuffer>][] = [
    ['image/jpeg', new Uint8Array([255, 216, 255])],
    ['image/gif', new TextEncoder().encode('GIF89a')],
    ['image/webp', new TextEncoder().encode('RIFF0000WEBP')],
    ['image/heic', new Uint8Array([0, 0, 0, 16, 102, 116, 121, 112, 104, 101, 105, 99, 0, 0, 0, 0])],
  ];
  const response = await upload(signatures.map(([type, bytes]) => new File([bytes], 'image', { type })));
  expect(response.status).toBe(201);
  const note = await response.json<Note>();
  expect(note.images.map(i => i.index)).toEqual([0, 1, 2, 3]);
  expect(note.images.map(i => i.content_type)).toEqual(signatures.map(([type]) => type));
});

it('retries return original images without any additional objects or metadata', async () => {
  const first = await upload(undefined, undefined, 'image-retry');
  expect(first.status).toBe(201);
  const note = await first.json<Note>();
  const before = await env.ATTACHMENTS.list({ prefix: 'notes/' });
  const response = await upload(undefined, undefined, 'image-retry', 'different');
  expect(response.status).toBe(200);
  expect(await response.json()).toEqual(note);
  expect((await env.ATTACHMENTS.list({ prefix: 'notes/' })).objects).toEqual(before.objects);
  const rows = await env.DB.prepare('SELECT * FROM session_note_images WHERE note_id = ?')
    .bind(note.id).all();
  expect(rows.results).toHaveLength(1);
});

it('concurrent retries retain one image set', async () => {
  const before = (await env.ATTACHMENTS.list({ prefix: 'notes/' })).objects.length;
  const responses = await Promise.all([upload(undefined, undefined, 'parallel-images'),
    upload(undefined, undefined, 'parallel-images')]);
  expect(responses.map(r => r.status).sort()).toEqual([200, 201]);
  const notes = await Promise.all(responses.map(r => r.json<Note>()));
  expect(notes[0]).toEqual(notes[1]);
  expect((await env.ATTACHMENTS.list({ prefix: 'notes/' })).objects).toHaveLength(before + 1);
  expect((await env.ATTACHMENTS.list({ prefix: `notes/${notes[0].id}/` })).objects).toHaveLength(1);
});

it('rolls back D1 rows and removes uploads when the metadata insertion fails', async () => {
  await env.DB.prepare(`CREATE TRIGGER reject_note_image BEFORE INSERT ON session_note_images
    BEGIN SELECT RAISE(ABORT, 'image insert rejected'); END`).run();
  const before = await env.DB.prepare('SELECT COUNT(*) AS n FROM session_notes').first();
  const objects = await env.ATTACHMENTS.list({ prefix: 'notes/' });
  try {
    expect((await upload(undefined, undefined, 'failed-images')).status).toBe(500);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM session_notes').first()).toEqual(before);
    expect(await env.DB.prepare("SELECT * FROM session_note_keys WHERE key = 'failed-images'").first())
      .toBeNull();
    expect((await env.ATTACHMENTS.list({ prefix: 'notes/' })).objects).toEqual(objects.objects);
  } finally {
    await env.DB.exec('DROP TRIGGER reject_note_image');
  }
});
