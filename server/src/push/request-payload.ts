// Builds questionnaire APNs payloads without a message or message snapshot.
// Exports prepareRequestPush and its panel/request context contract.
// Dependencies: shared boss decision tiers, privacy preferences, and priority types.

import type { Priority } from '../types';
import { decisionPushTier, isPrivatePush, type PreparedBossPush } from './boss-payload';

export interface RequestPushContext {
  panelId: string; requestId: string; bossId: string; agentName: string;
  panelTitle: string | null; title: string; priority: Priority;
}

export function prepareRequestPush(request: RequestPushContext, preferences: string | null): PreparedBossPush | null {
  const tier = decisionPushTier(request.priority, preferences);
  if (!tier.deliver) return null;
  const { panelId, requestId, bossId, agentName, panelTitle, title, priority } = request;
  return {
    apnsPriority: tier.apnsPriority,
    payload: {
      aps: {
        alert: { title: `${agentName} needs input`, ...(panelTitle ? { subtitle: panelTitle } : {}),
          body: isPrivatePush(preferences) ? 'Needs input' : title },
        category: 'HIBOSS_REQUEST', 'thread-id': bossId, 'interruption-level': tier.level,
        ...(tier.sound ? { sound: 'default' as const } : {}),
      },
      category: 'HIBOSS_REQUEST', panelId, requestId, agentName, priority,
    },
  };
}
