// Adds/removes explicit aliases without silently merging existing identities.
// Exports projectAliasesRouter; depends on agent auth and canonical lookup.
import { Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth } from '../middleware/auth';
import { parseProject } from './index';
import { lookupProject } from './inventory';

const routes = new Hono<{ Bindings: Env }>();
routes.use('*', apiAuth);

routes.post('/:project/aliases', async c => {
  const project = await lookupProject(c.env.DB, c.req.param('project'));
  if (!project) return c.text('project not found', 404);
  const body = await c.req.json<{ alias?: unknown }>().catch(() => null);
  if (typeof body?.alias !== 'string') return c.text('alias is required', 400);
  const parsed = parseProject(body.alias);
  if (!parsed || typeof parsed === 'string') return c.text(typeof parsed === 'string' ? parsed : 'alias is required', 400);
  const existing = await lookupProject(c.env.DB, body.alias);
  if (existing && existing.id !== project.id) return c.text('alias belongs to another project; use an explicit merge', 409);
  try {
    await c.env.DB.prepare("INSERT INTO project_aliases (alias, project_id, source) VALUES (?, ?, 'explicit') ON CONFLICT(alias) DO UPDATE SET project_id = CASE WHEN project_aliases.project_id = excluded.project_id THEN excluded.project_id ELSE NULL END")
      .bind(body.alias, project.id).run();
  } catch (error) {
    if (error instanceof Error && /UNIQUE|NOT NULL|FOREIGN KEY/.test(error.message)) return c.text('alias conflict', 409);
    throw error;
  }
  return c.json({ alias: body.alias, project_id: project.id }, 201);
});

routes.delete('/:project/aliases/:alias', async c => {
  const project = await lookupProject(c.env.DB, c.req.param('project'));
  if (!project) return c.text('project not found', 404);
  const alias = c.req.param('alias');
  if (alias === project.slug) return c.text('cannot remove the canonical slug alias', 400);
  const result = await c.env.DB.prepare('DELETE FROM project_aliases WHERE alias = ? AND project_id = ?').bind(alias, project.id).run();
  return result.meta.changes ? c.body(null, 204) : c.text('alias not found', 404);
});

export const projectAliasesRouter = routes;
