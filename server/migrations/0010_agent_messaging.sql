-- Cross-session agent-to-agent messaging (Layer 3).
-- Adds target_agent_id to messages for direct agent targeting.
-- Adds role and session_info to api_keys for session discovery.

ALTER TABLE messages ADD COLUMN target_agent_id TEXT;
ALTER TABLE api_keys ADD COLUMN role TEXT;
ALTER TABLE api_keys ADD COLUMN session_info TEXT;

CREATE INDEX idx_messages_target ON messages(target_agent_id);
