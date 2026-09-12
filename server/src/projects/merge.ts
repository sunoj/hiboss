// Builds atomic project reconciliation writes, including provenance in audit_log.
// Exports mergeStatements; depends on D1 and project identity types.
import type { Project } from './index';

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
