// Boss-scoped agent credential inventory, mint and revocation transport.
// Exports key metadata and request functions; depends on typed boss connections.
import { ApiError, type ConnectionConfig } from './types';
export type AgentKeyId = string & { readonly __brand: 'AgentKeyId' };
export interface AgentKey {
  id: AgentKeyId; agent_id: string; label: string; created_at: string;
  last_used_at: string | null; revoked_at: string | null;
}
export type KeyGrant = AgentKey & { key: string };
async function keyRequest(connection: ConnectionConfig, agentId: string, method: string, suffix = '', body?: { label: string }): Promise<Response> {
  const response = await fetch(`${connection.baseUrl}/api/boss/agents/${encodeURIComponent(agentId)}/keys${suffix}`, {
    method, headers: { Authorization: `Bearer ${connection.token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined
  });
  if (!response.ok) throw new ApiError(response.status, await response.text());
  return response;
}
export async function listAgentKeys(connection: ConnectionConfig, agentId: string): Promise<AgentKey[]> {
  const body = await (await keyRequest(connection, agentId, 'GET')).json() as { keys: AgentKey[] };
  return body.keys;
}
export async function mintAgentKey(connection: ConnectionConfig, agentId: string, label: string): Promise<KeyGrant> {
  return (await keyRequest(connection, agentId, 'POST', '', { label })).json() as Promise<KeyGrant>;
}
export async function revokeAgentKey(connection: ConnectionConfig, agentId: string, id: AgentKeyId): Promise<void> {
  await keyRequest(connection, agentId, 'DELETE', `/${encodeURIComponent(id)}`);
}
