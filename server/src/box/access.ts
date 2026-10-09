// Resolves Box reads through the existing panel boss policy.
// Boss credentials own their Box; agents can mutate only their own contributions.
import { HTTPException } from 'hono/http-exception';
import { getAgentId, getBossId, isBossAuth } from '../middleware/auth';
import { resolvedBosses } from '../panels/access';
import type { BoxContext, BoxRow, BoxWriteScope } from './types';

export async function boxBossIds(c: BoxContext): Promise<string[]> {
  if (isBossAuth(c)) return [getBossId(c)];
  return (await resolvedBosses(c.env.DB, getAgentId(c))).map(boss => boss.id);
}

export async function boxWriteScope(c: BoxContext, target: string | null): Promise<BoxWriteScope> {
  if (isBossAuth(c)) return { bossId: getBossId(c), agentId: null };
  const agentId = getAgentId(c);
  const bosses = await resolvedBosses(c.env.DB, agentId);
  if (target !== null) {
    const boss = bosses.find(boss => boss.id === target);
    if (boss) return { bossId: boss.id, agentId };
  }
  const matches = target === null ? bosses : bosses.filter(boss => boss.name === target);
  if (!matches.length) throw new HTTPException(404, { message: 'not found' });
  if (matches.length !== 1) {
    const choices = matches.map(boss => `${boss.name} (${boss.id})`).join(', ');
    throw new HTTPException(409, { message: `choose a boss: ${choices}` });
  }
  return { bossId: matches[0].id, agentId };
}

export function canEditItem(c: BoxContext, row: BoxRow): boolean {
  return isBossAuth(c) || row.agent_id === getAgentId(c);
}
