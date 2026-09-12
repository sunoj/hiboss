// Credential contracts independent of the api_keys agent identity.
// Exports key IDs, public metadata and audit actors; depends on D1 types.
export type AgentKeyId = string & { readonly __brand: 'AgentKeyId' };
export interface AgentKey {
  id: AgentKeyId;
  agent_id: string;
  label: string;
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
}
export interface KeyActor { type: 'agent' | 'boss' | 'system'; id: string }
export const KEY_COLUMNS = 'id, agent_id, label, created_at, last_used_at, revoked_at';
export const MAX_LABEL_LENGTH = 100;
