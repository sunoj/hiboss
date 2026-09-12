// Boss project inventory and explicit profile/merge administration.
// Exports bossProjectsRouter; depends on boss auth, scoped inventory and atomic merge.
import { Hono } from 'hono';
import type { Env } from '../types';
import { bossAuth, getBossId, getBossRole } from '../middleware/auth';
import { getAccessibleAgentIds } from '../routes/boss-api';
import { listProjects } from './inventory';
import { mergeStatements } from './merge';
import { isRecord } from '../routes/progress-helpers';

const routes = new Hono<{ Bindings: Env }>();
routes.use('*', bossAuth);

routes.get('/', async c => {
  const ids = await getAccessibleAgentIds(c.env, getBossId(c), getBossRole(c));
  return c.json({ projects: await listProjects(c.env.DB, ids, getBossRole(c) === 'admin') });
});

function validatePatch(body: unknown): string | null {
  if (!isRecord(body) || !Object.keys(body).length) return 'project patch is required';
  if (Object.keys(body).some(key => !['display_name', 'repo_url', 'merge_into'].includes(key))) return 'unknown project field';
  for (const [key, limit] of [['display_name', 256], ['repo_url', 2048], ['merge_into', 256]] as const) {
    if (body[key] === undefined || (key === 'repo_url' && body[key] === null)) continue;
    if (typeof body[key] !== 'string' || !body[key].trim() || body[key].length > limit) return `invalid ${key}`;
  }
  if (body.merge_into !== undefined && Object.keys(body).length !== 1) return 'merge must be a separate operation';
  if (typeof body.repo_url === 'string') {
    try { if (!['https:', 'http:'].includes(new URL(body.repo_url).protocol)) return 'invalid repo_url'; }
    catch { return 'invalid repo_url'; }
  }
  return null;
}

routes.patch('/:id', async c => {
  if (getBossRole(c) === 'viewer') return c.text('write access required', 403);
  const body: unknown = await c.req.json<unknown>().catch(() => null);
  const error = validatePatch(body);
  if (error || !isRecord(body)) return c.text(error ?? 'invalid patch', 400);
  const ids = await getAccessibleAgentIds(c.env, getBossId(c), getBossRole(c));
  const projects = await listProjects(c.env.DB, ids, getBossRole(c) === 'admin');
  const project = projects.find(row => row.id === c.req.param('id'));
  if (!project) return c.text('not found', 404);
  if (typeof body.merge_into === 'string') {
    const target = projects.find(row => row.id === body.merge_into);
    if (!target) return c.text('target not found', 404);
    if (target.id === project.id) return c.text('cannot merge a project into itself', 400);
    await c.env.DB.batch(mergeStatements(c.env.DB, target, [project], getBossId(c), 'boss'));
    return c.json({ id: target.id, slug: target.slug });
  }
  const sets: string[] = [];
  const values: (string | null)[] = [];
  for (const key of ['display_name', 'repo_url'] as const) {
    if (body[key] === undefined) continue;
    sets.push(`${key} = ?`); values.push(typeof body[key] === 'string' ? body[key].trim() : null);
  }
  await c.env.DB.batch([
    c.env.DB.prepare(`UPDATE projects SET ${sets.join(', ')}, updated_at = datetime('now') WHERE id = ?`).bind(...values, project.id),
    c.env.DB.prepare("INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details) VALUES ('boss', ?, 'project.update', 'project', ?, ?)")
      .bind(getBossId(c), project.id, JSON.stringify(body)),
  ]);
  return c.json({ id: project.id, slug: project.slug });
});

export const bossProjectsRouter = routes;
