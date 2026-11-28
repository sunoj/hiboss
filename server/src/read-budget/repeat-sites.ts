// Registry of every repeated-execution site in server/src that the static scan detects.
// Exports REPEAT_SITES: each site is metered by a read path or carries the reason it is not.
// Pure data, shared by scripts/poll-loops.check.ts (Node) and the Worker read-budget gate.

export interface RepeatSiteEntry {
  /** `<path under src>#<function>`, as printed by scripts/poll-loops.ts. */
  id: string;
  kind: 'loop' | 'interval' | 'alarm' | 'reschedule';
  /** Read-path ids in read-paths.ts that meter this site; empty only with `unmetered`. */
  paths: string[];
  unmetered?: string;
}

const PANEL_ALARM = 'Panel room retry alarm: armed only while a control operation is pending, and each '
  + 'retry reads and writes D1 rows by primary key (panel_id, operation_id).';

export const REPEAT_SITES: RepeatSiteEntry[] = [
  { id: 'routes/stream.ts#streamLoop', kind: 'loop', paths: ['agent-stream', 'agent-session-stream'] },
  { id: 'routes/boss-api-stream.ts#bossStreamLoop', kind: 'loop', paths: ['boss-message-stream'] },
  { id: 'routes/boss-option-stream.ts#streamBossOptions', kind: 'loop', paths: ['boss-option-stream'] },
  { id: 'routes/boss-feed-stream.ts#streamBossFeed', kind: 'loop', paths: ['boss-feed-stream'] },
  { id: 'routes/boss-required-input-stream.ts#streamBossRequiredInputs', kind: 'loop',
    paths: ['boss-required-input-stream'] },
  { id: 'routes/session-events.ts#streamLoop', kind: 'loop', paths: ['session-event-stream'] },
  { id: 'routes/messages.ts#routes.post(/:id/poll)', kind: 'loop', paths: ['agent-reply-long-poll'] },
  { id: 'panels/relay/runtime/engine.ts#PanelEngine.control', kind: 'alarm', paths: [], unmetered: PANEL_ALARM },
  { id: 'panels/relay/runtime/engine.ts#PanelEngine.finish', kind: 'alarm', paths: [], unmetered: PANEL_ALARM },
  { id: 'panels/relay/wall/signals.ts#WallSignals.schedule', kind: 'alarm', paths: [],
    unmetered: 'Panel wall expiry alarm: fires once per panel expiry time, then rechecks connected '
      + 'subscribers\' boss tokens by primary key (boss_tokens.id IN connected sockets).' },
];
