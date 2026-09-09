-- Store the current visibility deadline instead of deriving it from observations.
-- Existing panels get their window from migration time, not creation time: dating it from
-- created_at would put every card already past its deadline and empty the wall on deploy.
-- Dependencies: panels.lifecycle_json and SQLite JSON1/date functions.
UPDATE panels
SET lifecycle_json = json_set(
  lifecycle_json,
  '$.expiresAt', strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+' || json_extract(lifecycle_json, '$.ttlSeconds') || ' seconds')
)
WHERE json_extract(lifecycle_json, '$.expiresAt') IS NULL;
