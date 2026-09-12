// Shares session label SQL and additive project identity response mapping.
// Exports SESSION_LABEL_SQL and mapSessionProject; expects sessions s/projects p aliases.
const BRANCH = "COALESCE(s.branch, CASE WHEN instr(s.label, '/') > 0 THEN substr(s.label, instr(s.label, '/') + 1) ELSE '' END)";
export const SESSION_LABEL_SQL = `CASE WHEN p.slug IS NULL THEN s.label
  WHEN ${BRANCH} = '' THEN p.slug ELSE p.slug || '/' || ${BRANCH} END`;

export interface SessionProjectRow {
  project_id: string | null;
  project_slug: string | null;
  project_display_name: string | null;
}

export function mapSessionProject<T extends SessionProjectRow>({ project_display_name, ...row }: T):
  Omit<T, 'project_display_name'> & { project_ref: { id: string; slug: string; display_name: string } | null } {
  return { ...row, project_ref: row.project_id && row.project_slug ? {
    id: row.project_id, slug: row.project_slug, display_name: project_display_name ?? row.project_slug,
  } : null };
}
