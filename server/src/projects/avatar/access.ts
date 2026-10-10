// Authorizes avatar writes when every project participant, the caller included, shares an
// explicit active boss grant with the caller. Admin visibility covers every agent, so it
// never counts as shared. Exports avatarAccessError; depends on D1.

const PARTICIPANTS_SQL = `SELECT ?2 AS agent_id
  UNION SELECT agent_id FROM sessions WHERE project_id = ?1
  UNION SELECT agent_id FROM progress_posts WHERE project_id = ?1
  UNION SELECT created_by_agent_id FROM projects WHERE id = ?1 AND created_by_agent_id IS NOT NULL
  UNION SELECT s.agent_id FROM destination_routes r JOIN sessions s ON s.id = r.session_id WHERE r.project_id = ?1`;

const OUTSIDER_SQL = `SELECT 1 FROM (${PARTICIPANTS_SQL}) owners WHERE NOT EXISTS (
    SELECT 1 FROM boss_agent_access mine
    JOIN boss_agent_access theirs ON theirs.boss_id = mine.boss_id
    JOIN bosses b ON b.id = mine.boss_id AND b.archived_at IS NULL
    WHERE mine.agent_id = ?2 AND theirs.agent_id = owners.agent_id)
  LIMIT 1`;

export async function avatarAccessError(
  db: D1Database,
  projectId: string | null,
  agentId: string,
): Promise<string | null> {
  const session = await db.prepare('SELECT 1 FROM sessions WHERE project_id = ? AND agent_id = ? LIMIT 1')
    .bind(projectId, agentId).first();
  if (!session) return 'cannot set project avatar: you have no session on this project';
  const outsider = await db.prepare(OUTSIDER_SQL).bind(projectId, agentId).first();
  if (outsider) return 'cannot set project avatar: project has data from an agent outside your bosses';
  return null;
}
