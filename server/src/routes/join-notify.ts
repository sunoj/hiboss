// Sends join approval prompts to enrolled boss devices.
// Exports the join notifier used by agent enrollment.

import { pushJoinRequest, type JoinNotice } from '../devices/notify-push';
import type { Env } from '../types';

export function notifyJoinRequest(env: Env, notice: JoinNotice): Promise<void> {
  return pushJoinRequest(env, notice);
}
