-- An agent key minted by a boss lives only while that boss may still mint it (managers never
-- for boss-linked or is_admin agents). Backfill the minter from the mint audit, then retire
-- keys whose minter already lost that right, auditing each revocation.
ALTER TABLE agent_keys ADD COLUMN minted_by_boss_id TEXT;

UPDATE agent_keys SET minted_by_boss_id = (
  SELECT a.actor_id FROM audit_log a WHERE a.actor_type = 'boss' AND a.action = 'agent_key.mint'
    AND a.resource_type = 'agent_key' AND a.resource_id = agent_keys.id
  ORDER BY a.created_at LIMIT 1
);

CREATE INDEX idx_agent_keys_minted_by ON agent_keys(minted_by_boss_id) WHERE minted_by_boss_id IS NOT NULL;

INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
SELECT 'system', 'migration-0064', 'agent_key.revoke', 'agent_key', k.id,
  json_object('agent_id', k.agent_id, 'minted_by_boss_id', k.minted_by_boss_id)
FROM agent_keys k WHERE k.revoked_at IS NULL AND k.minted_by_boss_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM bosses minter WHERE minter.id = k.minted_by_boss_id AND minter.archived_at IS NULL
    AND (minter.role = 'admin' OR (minter.role = 'manager'
      AND EXISTS (SELECT 1 FROM boss_agent_access g WHERE g.boss_id = minter.id AND g.agent_id = k.agent_id)
      AND NOT EXISTS (SELECT 1 FROM bosses linked WHERE linked.agent_id = k.agent_id)
      AND NOT EXISTS (SELECT 1 FROM api_keys capable WHERE capable.id = k.agent_id AND capable.is_admin = 1))));

UPDATE agent_keys SET revoked_at = datetime('now')
WHERE id IN (SELECT resource_id FROM audit_log WHERE actor_id = 'migration-0064' AND action = 'agent_key.revoke');
