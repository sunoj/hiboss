-- Bind push devices and pairing codes to the boss token that registered or issued them.
-- A device or code is usable only while that token is live; rows without one are never used.
ALTER TABLE boss_devices ADD COLUMN token_id TEXT REFERENCES boss_tokens(id) ON DELETE CASCADE;
CREATE INDEX idx_boss_devices_token ON boss_devices(token_id);
UPDATE boss_devices SET token_id = (
  SELECT t.id FROM boss_tokens t
  WHERE t.client_id = boss_devices.client_id AND t.boss_id = boss_devices.boss_id AND t.revoked_at IS NULL
  ORDER BY t.created_at DESC, t.id DESC LIMIT 1
) WHERE client_id IS NOT NULL;
ALTER TABLE boss_pairing_codes ADD COLUMN issued_by_token_id TEXT REFERENCES boss_tokens(id) ON DELETE CASCADE;
