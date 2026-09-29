// Checks project data ownership and builds atomic reconciliation writes.
// Exports merge guards and mergeStatements; depends on D1 and project identity types.
import type { Project } from './index';

export async function hasForeignProjectSessions(db: D1Database, projects: Project[], agentId: string): Promise<boolean> {
  if (!projects.length) return false;
  const placeholders = projects.map(() => '?').join(', ');
  const row = await db.prepare(`SELECT 1 FROM sessions WHERE project_id IN (${placeholders}) AND agent_id != ? LIMIT 1`)
    .bind(...projects.map(project => project.id), agentId).first();
  return !!row;
}

export async function hasProjectDataOutsideBossGrant(db: D1Database, projectId: string, bossId: string): Promise<boolean> {
  const row = await db.prepare(`SELECT 1 FROM (
    SELECT agent_id FROM sessions WHERE project_id = ?
    UNION SELECT agent_id FROM progress_posts WHERE project_id = ?
    UNION SELECT s.agent_id FROM destination_routes r JOIN sessions s ON s.id = r.session_id WHERE r.project_id = ?
  ) owners WHERE NOT EXISTS (
    SELECT 1 FROM boss_agent_access access WHERE access.boss_id = ? AND access.agent_id = owners.agent_id
  ) LIMIT 1`).bind(projectId, projectId, projectId, bossId).first();
  return !!row;
}

export function mergeStatements(db: D1Database, winner: Project, absorbed: Project[], actorId: string, actorType: 'agent' | 'boss' = 'agent'): D1PreparedStatement[] {
  if (!absorbed.length) return [];
  const ids = absorbed.map(project => project.id);
  const placeholders = ids.map(() => '?').join(', ');
  const routeConflicts = db.prepare(`DELETE FROM destination_routes WHERE project_id IN (${placeholders})
    AND EXISTS (SELECT 1 FROM destination_routes keep
      WHERE keep.destination_id = destination_routes.destination_id
      AND COALESCE(keep.session_id, '') = COALESCE(destination_routes.session_id, '')
      AND (keep.project_id = ? OR (keep.project_id IN (${placeholders}) AND keep.id < destination_routes.id)))`)
    .bind(...ids, winner.id, ...ids);
  const statements = [routeConflicts, ...['sessions', 'progress_posts', 'destination_routes', 'project_aliases'].map(table =>
    db.prepare(`UPDATE ${table} SET project_id = ? WHERE project_id IN (${placeholders})`).bind(winner.id, ...ids))];
  statements.push(db.prepare(`DELETE FROM projects WHERE id IN (${placeholders})`).bind(...ids));
  statements.push(db.prepare("INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details) VALUES (?, ?, 'project.merge', 'project', ?, ?)")
    .bind(actorType, actorId, winner.id, JSON.stringify({ absorbed_ids: ids })));
  return statements;
}
