-- Add the panel visibility window to existing lifecycle records.
-- Existing panels retain their state and receive the safe default window.
-- Dependencies: panels and the JSON1 functions available in D1.
UPDATE panels
SET lifecycle_json = json_set(
  COALESCE(lifecycle_json, '{}'),
  '$.ttlSeconds', COALESCE(json_extract(lifecycle_json, '$.ttlSeconds'), 3600),
  '$.lastObservedAt', COALESCE(json_extract(lifecycle_json, '$.lastObservedAt'), NULL)
)
WHERE json_extract(lifecycle_json, '$.ttlSeconds') IS NULL
   OR json_extract(lifecycle_json, '$.lastObservedAt') IS NULL;
