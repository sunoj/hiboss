// Validates CLI-selected nicknames and allocates collision suffixes inside a session write.
// Exports parseSessionNickname and SESSION_NICKNAME_SQL; depends on SQLite sessions.

export function parseSessionNickname(value: unknown): string | null | Error {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || !/^[a-z]{3,12}(?:-(?:[2-9]|[1-9][0-9]+))?$/.test(value)) {
    return new Error('nickname is malformed');
  }
  return value;
}

// Binds (sessionId, requestedNickname, projectId). A null projectId uses the stored project.
// Prefer the stored nickname, then the first free base/suffix. Each write sees all prior
// writes, including concurrent registrations; completed and >24h-old rows reserve nothing.
export const SESSION_NICKNAME_SQL = `(WITH RECURSIVE
  input(id, requested, project) AS (VALUES (?, ?, ?)),
  preferred AS (
    SELECT COALESCE(s.nickname, i.requested) AS value, COALESCE(i.project, s.project_id) AS project
    FROM input i LEFT JOIN sessions s ON s.id = i.id
  ),
  live AS (
    SELECT nickname FROM sessions WHERE project_id = (SELECT project FROM preferred)
      AND id <> (SELECT id FROM input) AND nickname IS NOT NULL
      AND status <> 'completed' AND last_seen_at > datetime('now', '-24 hours')
  ),
  base AS (
    SELECT CASE WHEN instr(value, '-') > 0 THEN substr(value, 1, instr(value, '-') - 1)
      ELSE value END AS value FROM preferred
  ),
  numbers(n) AS (
    SELECT 1 UNION ALL SELECT n + 1 FROM numbers WHERE n <= (SELECT COUNT(*) FROM live)
  ),
  candidates(value, rank) AS (
    SELECT value, 0 FROM preferred UNION ALL
    SELECT CASE WHEN n = 1 THEN value ELSE value || '-' || n END, n FROM base, numbers
  )
  SELECT value FROM candidates WHERE value IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM live WHERE nickname = candidates.value)
  ORDER BY rank LIMIT 1)`;
