// Shares the displayed session label between listing and target lookup.
// Exports a D1 select expression; expects sessions s and projects p aliases.
const BRANCH = "COALESCE(s.branch, CASE WHEN instr(s.label, '/') > 0 THEN substr(s.label, instr(s.label, '/') + 1) ELSE '' END)";
export const SESSION_LABEL_SQL = `CASE WHEN p.slug IS NULL THEN s.label
  WHEN ${BRANCH} = '' THEN p.slug ELSE p.slug || '/' || ${BRANCH} END`;
