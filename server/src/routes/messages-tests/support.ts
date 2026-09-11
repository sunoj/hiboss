// Agent fixture creation for message API regression suites.
// Exports createAgentAuth; depends on D1 and API key hashing.
import { env } from 'cloudflare:test';
import { hashApiKey } from '../../middleware/auth';

export async function createAgentAuth(agentId: string, apiKey: string): Promise<Record<string, string>> {
  const keyHash = await hashApiKey(apiKey);
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agentId, agentId, keyHash)
    .run();
  return {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
  };
}
