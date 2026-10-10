// Authorizes avatar writes for project session participants with overlapping bosses.
// Exports avatarAccessError; depends on D1 and the shared resolvedBosses policy.
import { resolvedBosses } from '../../panels/access';

export async function avatarAccessError(
  db: D1Database,
  projectId: string | null,
  agentId: string,
): Promise<string | null> {
  const owners = await db.prepare('SELECT DISTINCT agent_id FROM sessions WHERE project_id = ?')
    .bind(projectId).all<{ agent_id: string }>();
  if (!owners.results.some(owner => owner.agent_id === agentId)) {
    return 'cannot set project avatar: you have no session on this project';
  }
  const bosses = new Set((await resolvedBosses(db, agentId)).map(boss => boss.id));
  for (const owner of owners.results) {
    const ownerBosses = owner.agent_id === agentId
      ? [...bosses] : (await resolvedBosses(db, owner.agent_id)).map(boss => boss.id);
    if (!ownerBosses.some(id => bosses.has(id))) {
      return 'cannot set project avatar: project has a session from an agent outside your bosses';
    }
  }
  return null;
}
