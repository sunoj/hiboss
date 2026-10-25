-- Bind push devices and pairing codes to the boss token that registered or issued them.
-- A device or code is usable only while that token is live; rows without one are never used.
ALTER TABLE boss_devices ADD COLUMN token_id TEXT REFERENCES boss_tokens(id) ON DELETE CASCADE;
CREATE INDEX idx_boss_devices_token ON boss_devices(token_id);
UPDATE boss_devices SET token_id = (
  SELECT t.id FROM boss_tokens t
  WHERE t.client_id = boss_devices.client_id AND t.boss_id = boss_devices.boss_id AND t.revoked_at IS NULL
  ORDER BY t.created_at DESC, t.id DESC LIMIT 1
) WHERE client_id IS NOT NULL;
-- A device registered under a client-less token keeps pushing under the boss's newest such token
-- that existed when it last registered; a later rotation token never adopts an earlier device.
UPDATE boss_devices SET token_id = (
  SELECT t.id FROM boss_tokens t
  WHERE t.boss_id = boss_devices.boss_id AND t.client_id IS NULL AND t.revoked_at IS NULL
    AND t.created_at <= boss_devices.updated_at
  ORDER BY t.created_at DESC, t.id DESC LIMIT 1
) WHERE token_id IS NULL AND client_id IS NULL;
ALTER TABLE boss_pairing_codes ADD COLUMN issued_by_token_id TEXT REFERENCES boss_tokens(id) ON DELETE CASCADE;
