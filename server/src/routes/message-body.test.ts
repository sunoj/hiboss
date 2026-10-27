// Verifies long agent bodies survive send, blocking ask, and edits without client metadata changes.
// Exercises Worker routes and D1 storage, including the existing surrounding-whitespace trim.
import { testRequest } from '../test-request';
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import type { Mode } from '../types';
import { authHeaders, seedDatabase } from '../test-helpers';

const bodies = [
  { label: '145 ASCII scalars', body: 'x'.repeat(145) },
  { label: '145 CJK scalars', body: '字'.repeat(145) },
  { label: '145 emoji scalars', body: '🏠'.repeat(145) },
  { label: '10k-character single line', body: 'x'.repeat(10_000) },
];
const metadataCases: { label: string; metadata: Record<string, unknown> | undefined }[] = [
  { label: 'absent metadata', metadata: undefined },
  {
    label: 'existing metadata',
    metadata: {
      content: '# Details\n\n```text\n  Keep this whitespace  \n```\n',
      summary: 'Notification preview',
      custom: { retained: true, values: ['one', 2] },
    },
  },
];

beforeAll(seedDatabase);

async function createMessage(
  body: string, mode: Mode, metadata: Record<string, unknown> | undefined,
): Promise<string> {
  const response = await testRequest('POST', 'https://test.local/api/messages', authHeaders(),
    { body, mode, metadata });
  expect(response.status).toBe(201);
  return (await response.json() as { id: string }).id;
}

/** Client metadata survives unchanged; the server adds only its own attribution keys. */
function clientMetadata(value: unknown): Record<string, unknown> | null {
  const record = { ...(value as Record<string, unknown>) };
  expect(record['source']).toBe('agent');
  expect(record['provenance']).toMatchObject({ source: 'agent', actor: { kind: 'agent', id: 'test-agent-id' } });
  delete record['source'];
  delete record['provenance'];
  return Object.keys(record).length > 0 ? record : null;
}

async function expectStoredMessage(
  id: string, body: string, mode: Mode, metadata: Record<string, unknown> | undefined,
): Promise<void> {
  const stored = await env.DB.prepare('SELECT body, mode, metadata FROM messages WHERE id = ?')
    .bind(id).first<{ body: string; mode: Mode; metadata: string | null }>();
  expect(stored).toMatchObject({ body, mode });
  expect(clientMetadata(JSON.parse(stored?.metadata ?? 'null'))).toEqual(metadata ?? null);
  const detail = await SELF.fetch(`https://test.local/api/messages/${id}`, { headers: authHeaders() });
  expect(detail.status).toBe(200);
  const message = await detail.json() as { body: string; mode: Mode; metadata: unknown };
  expect(message.body).toBe(body);
  expect(message.mode).toBe(mode);
  expect(clientMetadata(message.metadata)).toEqual(metadata ?? null);
}

describe('Long agent message bodies', () => {
  for (const { label, body } of bodies) {
    for (const { label: metadataLabel, metadata } of metadataCases) {
      for (const mode of ['async', 'blocking'] as const) {
        const action = mode === 'blocking' ? 'ask' : 'send';
        it(`accepts ${label} on ${action} with ${metadataLabel} and preserves trimmed storage`, async () => {
          const id = await createMessage(` \t\n\u2003${body}\u2003\n\t `, mode, metadata);
          await expectStoredMessage(id, body, mode, metadata);
        });
      }

      it(`accepts ${label} on PATCH with ${metadataLabel} and preserves trimmed storage`, async () => {
        const id = await createMessage('Ready', 'async', metadata);
        const response = await testRequest('PATCH', `https://test.local/api/messages/${id}`, authHeaders(),
          { body: ` \t\n\u2003${body}\u2003\n\t ` });
        expect(response.status).toBe(200);
        await expectStoredMessage(id, body, 'async', metadata);
      });
    }
  }
});
