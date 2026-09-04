-- Links a consumed one-time pairing code to the token created from it.
-- Enables the issuing Mac to observe completed enrollment without exposing credentials.
ALTER TABLE boss_pairing_codes
ADD COLUMN redeemed_token_id TEXT REFERENCES boss_tokens(id) ON DELETE SET NULL;
