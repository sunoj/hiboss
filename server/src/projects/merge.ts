// Builds atomic project reconciliation writes, including provenance in audit_log.
// Exports mergeStatements; depends on D1 and project identity types.
import type { Project } from './index';

export function mergeStatements(db: D1Database, winner: Project, absorbed: Project[], agentId: string): D1PreparedStatement[] {
  if (!absorbed.length) return [];
  const ids = absorbed.map(project => project.id);
  const placeholders = ids.map(() => '?').join(', ');
  const statements = ['sessions', 'progress_posts', 'destination_routes', 'project_aliases'].map(table =>
    db.prepare(`UPDATE ${table} SET project_id = ? WHERE project_id IN (${placeholders})`).bind(winner.id, ...ids));
  statements.push(db.prepare(`DELETE FROM projects WHERE id IN (${placeholders})`).bind(...ids));
  statements.push(db.prepare("INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details) VALUES ('agent', ?, 'project.merge', 'project', ?, ?)")
    .bind(agentId, winner.id, JSON.stringify({ absorbed_ids: ids })));
  return statements;
}
