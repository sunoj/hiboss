ALTER TABLE agent_groups ADD COLUMN owner_id TEXT REFERENCES api_keys(id);
UPDATE agent_groups
SET owner_id = (
  SELECT agent_id
  FROM agent_group_members
  WHERE group_id = agent_groups.id
  LIMIT 1
);
