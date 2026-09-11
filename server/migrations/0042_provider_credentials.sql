-- Consolidate providers by effective credential without losing destinations.
-- Uses SQLite JSON expressions shared by the uniqueness guard.
-- Retain the smallest provider ID and repoint references before removing duplicates.
UPDATE boss_destinations SET provider_id = (
  SELECT MIN(p.id) FROM channel_providers p
  WHERE COALESCE(NULLIF(json_extract(p.credentials, '$.webhook_url'), ''), json_extract(p.credentials, '$.bot_token'), '') = (
    SELECT COALESCE(NULLIF(json_extract(credentials, '$.webhook_url'), ''), json_extract(credentials, '$.bot_token'), '')
    FROM channel_providers WHERE id = boss_destinations.provider_id
  )
) WHERE provider_id IS NOT NULL;
DELETE FROM channel_providers WHERE id NOT IN (
  SELECT MIN(id) FROM channel_providers GROUP BY
    COALESCE(NULLIF(json_extract(credentials, '$.webhook_url'), ''), json_extract(credentials, '$.bot_token'), '')
);
CREATE UNIQUE INDEX idx_channel_providers_effective_credential ON channel_providers(
  COALESCE(NULLIF(json_extract(credentials, '$.webhook_url'), ''), json_extract(credentials, '$.bot_token'), '')
);
