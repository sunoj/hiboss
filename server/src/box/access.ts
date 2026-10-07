// Resolves Box reads through the existing panel boss policy.
// Boss credentials are scoped to their own Box; agents have no mutations.
import { getAgentId, getBossId, isBossAuth } from '../middleware/auth';
import { resolvedBosses } from '../panels/access';
import type { BoxContext } from './types';

export async function boxBossIds(c: BoxContext): Promise<string[]> {
  if (isBossAuth(c)) return [getBossId(c)];
  return (await resolvedBosses(c.env.DB, getAgentId(c))).map(boss => boss.id);
}
