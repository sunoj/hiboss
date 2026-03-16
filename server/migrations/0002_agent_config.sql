-- Add agent-level configuration: default priority and rate limiting
ALTER TABLE api_keys ADD COLUMN default_priority TEXT NOT NULL DEFAULT 'normal' CHECK (default_priority IN ('critical', 'high', 'normal', 'low'));
ALTER TABLE api_keys ADD COLUMN rate_limit INTEGER;  -- max messages per minute, NULL = unlimited
