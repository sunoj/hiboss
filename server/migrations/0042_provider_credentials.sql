-- Backfill SHA-256 credential identity and consolidate duplicate providers without losing destinations.
-- Uses portable SQLite integer/JSON operations (D1 has no SHA-256 SQL extension).
ALTER TABLE channel_providers ADD COLUMN credential_hash TEXT;

-- SHA-256 padding over UTF-8 bytes, then parse big-endian 32-bit message words.
CREATE TABLE credential_hash_words AS
WITH RECURSIVE
credentials AS (
  SELECT id, hex(CAST(COALESCE(NULLIF(json_extract(credentials, '$.webhook_url'), ''),
    json_extract(credentials, '$.bot_token'), '') AS BLOB)) AS bytes FROM channel_providers
),
padded AS (
  SELECT id, bytes || '80' || substr(printf('%0128d', 0), 1, (238 - length(bytes) % 128) % 128)
    || printf('%016x', length(bytes) * 4) AS bytes FROM credentials
),
nibbles(id, bytes, pos, word) AS (
  SELECT id, bytes, 0, 0 FROM padded
  UNION ALL
  SELECT id, bytes, pos + 1, (CASE WHEN pos % 8 = 0 THEN 0 ELSE word END) * 16
    + instr('0123456789ABCDEF', upper(substr(bytes, pos + 1, 1))) - 1
  FROM nibbles WHERE pos < length(bytes)
),
blocks AS (
  SELECT id, (pos - 1) / 128 AS block, json_group_array(word) AS w
  FROM (SELECT * FROM nibbles WHERE pos > 0 AND pos % 8 = 0 ORDER BY id, pos)
  GROUP BY id, (pos - 1) / 128
),
schedule(id, block, n, w) AS (
  SELECT id, block, 16, w FROM blocks
  UNION ALL
  SELECT id, block, n + 1, json_insert(w, '$[#]', (
    json_extract(w, '$[' || (n - 16) || ']') + json_extract(w, '$[' || (n - 7) || ']')
    + (((((((json_extract(w, '$[' || (n - 15) || ']')) >> 7) | (((json_extract(w, '$[' || (n - 15) || ']')) << 25) & 4294967295)) | (((json_extract(w, '$[' || (n - 15) || ']')) >> 18) | (((json_extract(w, '$[' || (n - 15) || ']')) << 14) & 4294967295))) - ((((json_extract(w, '$[' || (n - 15) || ']')) >> 7) | (((json_extract(w, '$[' || (n - 15) || ']')) << 25) & 4294967295)) & (((json_extract(w, '$[' || (n - 15) || ']')) >> 18) | (((json_extract(w, '$[' || (n - 15) || ']')) << 14) & 4294967295)))) | ((json_extract(w, '$[' || (n - 15) || ']')) >> 3)) - ((((((json_extract(w, '$[' || (n - 15) || ']')) >> 7) | (((json_extract(w, '$[' || (n - 15) || ']')) << 25) & 4294967295)) | (((json_extract(w, '$[' || (n - 15) || ']')) >> 18) | (((json_extract(w, '$[' || (n - 15) || ']')) << 14) & 4294967295))) - ((((json_extract(w, '$[' || (n - 15) || ']')) >> 7) | (((json_extract(w, '$[' || (n - 15) || ']')) << 25) & 4294967295)) & (((json_extract(w, '$[' || (n - 15) || ']')) >> 18) | (((json_extract(w, '$[' || (n - 15) || ']')) << 14) & 4294967295)))) & ((json_extract(w, '$[' || (n - 15) || ']')) >> 3)))
    + (((((((json_extract(w, '$[' || (n - 2) || ']')) >> 17) | (((json_extract(w, '$[' || (n - 2) || ']')) << 15) & 4294967295)) | (((json_extract(w, '$[' || (n - 2) || ']')) >> 19) | (((json_extract(w, '$[' || (n - 2) || ']')) << 13) & 4294967295))) - ((((json_extract(w, '$[' || (n - 2) || ']')) >> 17) | (((json_extract(w, '$[' || (n - 2) || ']')) << 15) & 4294967295)) & (((json_extract(w, '$[' || (n - 2) || ']')) >> 19) | (((json_extract(w, '$[' || (n - 2) || ']')) << 13) & 4294967295)))) | ((json_extract(w, '$[' || (n - 2) || ']')) >> 10)) - ((((((json_extract(w, '$[' || (n - 2) || ']')) >> 17) | (((json_extract(w, '$[' || (n - 2) || ']')) << 15) & 4294967295)) | (((json_extract(w, '$[' || (n - 2) || ']')) >> 19) | (((json_extract(w, '$[' || (n - 2) || ']')) << 13) & 4294967295))) - ((((json_extract(w, '$[' || (n - 2) || ']')) >> 17) | (((json_extract(w, '$[' || (n - 2) || ']')) << 15) & 4294967295)) & (((json_extract(w, '$[' || (n - 2) || ']')) >> 19) | (((json_extract(w, '$[' || (n - 2) || ']')) << 13) & 4294967295)))) & ((json_extract(w, '$[' || (n - 2) || ']')) >> 10)))
  ) & 4294967295) FROM schedule WHERE n < 64
)
SELECT id, block, w FROM schedule WHERE n = 64;

-- Compression phases: calculate T1/T2, shift working words, then accumulate each block.
CREATE TABLE credential_hash_results AS
WITH RECURSIVE
constants(k) AS (VALUES ('[1116352408,1899447441,3049323471,3921009573,961987163,1508970993,2453635748,2870763221,3624381080,310598401,607225278,1426881987,1925078388,2162078206,2614888103,3248222580,3835390401,4022224774,264347078,604807628,770255983,1249150122,1555081692,1996064986,2554220882,2821834349,2952996808,3210313671,3336571891,3584528711,113926993,338241895,666307205,773529912,1294757372,1396182291,1695183700,1986661051,2177026350,2456956037,2730485921,2820302411,3259730800,3345764771,3516065817,3600352804,4094571909,275423344,430227734,506948616,659060556,883997877,958139571,1322822218,1537002063,1747873779,1955562222,2024104815,2227730452,2361852424,2428436474,2756734187,3204031479,3329325298]')),
compression(id, n, phase, a, b, c, d, e, f, g, h, ha, hb, hc, hd, he, hf, hg, hh, t1, t2) AS (
  SELECT id, 0, 0, 1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225,
    1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225, 0, 0
  FROM channel_providers
  UNION ALL
  SELECT s.id, n + CASE WHEN phase = 2 THEN 1 ELSE 0 END, (phase + 1) % 3,
    CASE phase WHEN 1 THEN (t1 + t2) & 4294967295 WHEN 2 THEN (a + CASE WHEN n % 64 = 63 THEN ha ELSE 0 END) & 4294967295 ELSE a END,
    CASE phase WHEN 1 THEN a WHEN 2 THEN (b + CASE WHEN n % 64 = 63 THEN hb ELSE 0 END) & 4294967295 ELSE b END,
    CASE phase WHEN 1 THEN b WHEN 2 THEN (c + CASE WHEN n % 64 = 63 THEN hc ELSE 0 END) & 4294967295 ELSE c END,
    CASE phase WHEN 1 THEN c WHEN 2 THEN (d + CASE WHEN n % 64 = 63 THEN hd ELSE 0 END) & 4294967295 ELSE d END,
    CASE phase WHEN 1 THEN (d + t1) & 4294967295 WHEN 2 THEN (e + CASE WHEN n % 64 = 63 THEN he ELSE 0 END) & 4294967295 ELSE e END,
    CASE phase WHEN 1 THEN e WHEN 2 THEN (f + CASE WHEN n % 64 = 63 THEN hf ELSE 0 END) & 4294967295 ELSE f END,
    CASE phase WHEN 1 THEN f WHEN 2 THEN (g + CASE WHEN n % 64 = 63 THEN hg ELSE 0 END) & 4294967295 ELSE g END,
    CASE phase WHEN 1 THEN g WHEN 2 THEN (h + CASE WHEN n % 64 = 63 THEN hh ELSE 0 END) & 4294967295 ELSE h END,
    CASE WHEN phase = 2 AND n % 64 = 63 THEN (a + ha) & 4294967295 ELSE ha END,
    CASE WHEN phase = 2 AND n % 64 = 63 THEN (b + hb) & 4294967295 ELSE hb END,
    CASE WHEN phase = 2 AND n % 64 = 63 THEN (c + hc) & 4294967295 ELSE hc END,
    CASE WHEN phase = 2 AND n % 64 = 63 THEN (d + hd) & 4294967295 ELSE hd END,
    CASE WHEN phase = 2 AND n % 64 = 63 THEN (e + he) & 4294967295 ELSE he END,
    CASE WHEN phase = 2 AND n % 64 = 63 THEN (f + hf) & 4294967295 ELSE hf END,
    CASE WHEN phase = 2 AND n % 64 = 63 THEN (g + hg) & 4294967295 ELSE hg END,
    CASE WHEN phase = 2 AND n % 64 = 63 THEN (h + hh) & 4294967295 ELSE hh END,
    CASE WHEN phase = 0 THEN (h + ((e & f) | ((~e) & g))
      + json_extract(k, '$[' || (n % 64) || ']') + json_extract(w, '$[' || (n % 64) || ']')
      + (((((((e) >> 6) | (((e) << 26) & 4294967295)) | (((e) >> 11) | (((e) << 21) & 4294967295))) - ((((e) >> 6) | (((e) << 26) & 4294967295)) & (((e) >> 11) | (((e) << 21) & 4294967295)))) | (((e) >> 25) | (((e) << 7) & 4294967295))) - ((((((e) >> 6) | (((e) << 26) & 4294967295)) | (((e) >> 11) | (((e) << 21) & 4294967295))) - ((((e) >> 6) | (((e) << 26) & 4294967295)) & (((e) >> 11) | (((e) << 21) & 4294967295)))) & (((e) >> 25) | (((e) << 7) & 4294967295))))) & 4294967295 ELSE t1 END,
    CASE WHEN phase = 0 THEN (((a & b) | (a & c) | (b & c))
      + (((((((a) >> 2) | (((a) << 30) & 4294967295)) | (((a) >> 13) | (((a) << 19) & 4294967295))) - ((((a) >> 2) | (((a) << 30) & 4294967295)) & (((a) >> 13) | (((a) << 19) & 4294967295)))) | (((a) >> 22) | (((a) << 10) & 4294967295))) - ((((((a) >> 2) | (((a) << 30) & 4294967295)) | (((a) >> 13) | (((a) << 19) & 4294967295))) - ((((a) >> 2) | (((a) << 30) & 4294967295)) & (((a) >> 13) | (((a) << 19) & 4294967295)))) & (((a) >> 22) | (((a) << 10) & 4294967295))))) & 4294967295 ELSE t2 END
  FROM compression s JOIN credential_hash_words words ON words.id = s.id AND words.block = n / 64
  CROSS JOIN constants
)
SELECT id, printf('%08x%08x%08x%08x%08x%08x%08x%08x', a, b, c, d, e, f, g, h) AS hash
FROM compression WHERE phase = 0 AND n = (SELECT COUNT(*) * 64 FROM credential_hash_words w WHERE w.id = compression.id);

UPDATE channel_providers SET credential_hash = (SELECT hash FROM credential_hash_results WHERE id = channel_providers.id);
DROP TABLE credential_hash_results;
DROP TABLE credential_hash_words;

-- Retain the smallest provider ID and repoint references before removing duplicates.
UPDATE boss_destinations SET provider_id = (
  SELECT MIN(p.id) FROM channel_providers p
  WHERE p.credential_hash = (SELECT credential_hash FROM channel_providers WHERE id = boss_destinations.provider_id)
) WHERE provider_id IS NOT NULL;
DELETE FROM channel_providers WHERE id NOT IN (SELECT MIN(id) FROM channel_providers GROUP BY credential_hash);
CREATE UNIQUE INDEX idx_channel_providers_credential_hash ON channel_providers(credential_hash);
-- Direct SQL writers cannot bypass uniqueness by omitting or miscomputing the hash.
CREATE UNIQUE INDEX idx_channel_providers_effective_credential ON channel_providers(
  COALESCE(NULLIF(json_extract(credentials, '$.webhook_url'), ''), json_extract(credentials, '$.bot_token'), '')
);
