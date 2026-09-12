// Project inventory and mutation transport coverage, including failure propagation.
// Uses Vitest fetch stubs; actual console interaction runs remotely in Playwright.
import { afterEach, expect, it, vi } from 'vitest';
import { listProjects, patchProject, type ProjectId } from './projects';
const connection = { baseUrl: 'https://test.local', token: 'boss-token' };
afterEach(() => vi.unstubAllGlobals());

it('lists canonical projects and preserves session-only timestamps', async () => {
  const projects = [{ id: 'p', slug: 'repo', display_name: 'Repo', aliases: ['old'], session_count: 1, last_post_at: null }];
  const fetcher = vi.fn().mockResolvedValue(new Response(JSON.stringify({ projects })));
  vi.stubGlobal('fetch', fetcher);
  expect(await listProjects(connection)).toEqual(projects);
  expect(fetcher).toHaveBeenCalledWith('https://test.local/api/boss/projects', {
    headers: { Authorization: 'Bearer boss-token' }
  });
});

it('sends an explicit source-to-target merge and surfaces rejection', async () => {
  const fetcher = vi.fn().mockResolvedValue(new Response('denied', { status: 403 }));
  vi.stubGlobal('fetch', fetcher);
  await expect(patchProject(connection, 'source' as ProjectId, { merge_into: 'target' as ProjectId })).rejects.toThrow('denied');
  expect(fetcher).toHaveBeenCalledWith('https://test.local/api/boss/projects/source', expect.objectContaining({
    method: 'PATCH', body: JSON.stringify({ merge_into: 'target' })
  }));
});
