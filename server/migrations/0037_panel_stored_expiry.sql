-- Store the current visibility deadline instead of deriving it from observations.
-- Existing panels receive one deadline during migration; future publications set it explicitly.
-- Dependencies: panels.lifecycle_json and SQLite JSON1/date functions.
UPDATE panels
SET lifecycle_json = json_set(
  lifecycle_json,
  '$.expiresAt', strftime('%Y-%m-%dT%H:%M:%fZ', created_at, '+' || json_extract(lifecycle_json, '$.ttlSeconds') || ' seconds')
)
WHERE json_extract(lifecycle_json, '$.expiresAt') IS NULL;
