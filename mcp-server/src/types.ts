// Describes hiboss message messages shared across MCP helpers.
// Exports the shape the hiboss API returns to keep other modules typed.
// Depends only on the hiboss HTTP contract documented in CLAUDE.md.

export type HibossMessage = {
  id: string;
  body: string;
  channel: string;
  status: string;
  direction: 'agent_to_boss' | 'boss_to_agent';
  mode: 'async' | 'blocking';
  priority?: string;
  reply_to: string | null;
  created_at: string;
  updated_at: string;
  replies?: HibossMessage[];
};

export type HibossListResponse = { messages: HibossMessage[]; total: number };
