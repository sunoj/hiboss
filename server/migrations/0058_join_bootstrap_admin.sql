-- Persist bootstrap eligibility until a boss approves the requested profiles.
-- Existing and invited requests retain ordinary agent capabilities.
ALTER TABLE join_requests ADD COLUMN bootstrap_admin INTEGER NOT NULL DEFAULT 0
  CHECK (bootstrap_admin IN (0, 1));
