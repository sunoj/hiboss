// Credential API transport coverage for metadata, one-time mint and denied revocation.
// Uses Vitest fetch stubs; browser flows are executed on the remote E2E host.
import { afterEach, expect, it, vi } from 'vitest';
import { listAgentKeys, mintAgentKey, revokeAgentKey, type AgentKeyId } from './agent-keys';
const connection = { baseUrl: 'https://test.local', token: 'boss-key' };
afterEach(() => vi.unstubAllGlobals());
it('lists metadata under the encoded agent scope', async () => {
  const fetcher = vi.fn().mockResolvedValue(new Response('{"keys":[{"id":"key","label":"Mac"}]}'));
  vi.stubGlobal('fetch', fetcher);
  expect(await listAgentKeys(connection, 'agent/id')).toEqual([{ id: 'key', label: 'Mac' }]);
  expect(fetcher).toHaveBeenCalledWith('https://test.local/api/boss/agents/agent%2Fid/keys', expect.objectContaining({ method: 'GET' }));
});
it('mints a labelled bearer with boss authorization', async () => {
  const fetcher = vi.fn().mockResolvedValue(new Response('{"id":"new","key":"hb_once"}'));
  vi.stubGlobal('fetch', fetcher);
  expect((await mintAgentKey(connection, 'agent', 'Linux')).key).toBe('hb_once');
  expect(fetcher).toHaveBeenCalledWith(expect.any(String), expect.objectContaining({
    method: 'POST', body: '{"label":"Linux"}', headers: expect.objectContaining({ Authorization: 'Bearer boss-key' })
  }));
});
it('surfaces denied revocation instead of claiming success', async () => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('denied', { status: 403 })));
  await expect(revokeAgentKey(connection, 'agent', 'key' as AgentKeyId)).rejects.toThrow('denied');
});
