-- Add avatar_url to agent profiles for per-agent avatar in Discord webhook messages
ALTER TABLE api_keys ADD COLUMN avatar_url TEXT;
