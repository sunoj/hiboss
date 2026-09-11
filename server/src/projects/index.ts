// Resolves project identities and validates session ownership for agent writes.
// Exports project parsing/resolution and ownership checks; depends on D1.
export type ProjectId = string & { readonly __brand: 'ProjectId' };
export type AliasSource = 'origin' | 'cwd' | 'explicit' | 'label';
export interface ProjectInput {
  slug: string;
  aliases: string[];
  display_name?: string;
  repo_url?: string;
}
export interface Project { id: ProjectId; slug: string }
type Resolution = { ok: true; project: Project } | { ok: false; error: string };

export function projectSlug(value: string): string {
  return value.trim().toLowerCase().replace(/[^a-z0-9_]+/g, '-').replace(/^-+|-+$/g, '') || 'project';
}

export function parseProject(value: unknown): ProjectInput | string | null {
  if (value === undefined || value === null) return null;
  if (typeof value === 'string') return value.trim() ? { slug: value, aliases: [value] } : 'project must not be empty';
  if (typeof value !== 'object' || Array.isArray(value)) return 'project must be text or an object';
  const input = value as Record<string, unknown>;
  if (typeof input.slug !== 'string' || !input.slug.trim()) return 'project.slug must not be empty';
  if (!Array.isArray(input.aliases) || input.aliases.length > 32
    || input.aliases.some(alias => typeof alias !== 'string' || !alias.trim() || alias.length > 256)) {
    return 'project.aliases must contain at most 32 non-empty strings (max 256 characters)';
  }
  if (input.slug.length > 256) return 'project.slug is too long';
  for (const key of ['display_name', 'repo_url']) {
    if (input[key] !== undefined && (typeof input[key] !== 'string' || !input[key].trim())) return `project.${key} must be non-empty text`;
  }
  return { slug: input.slug, aliases: input.aliases as string[], display_name: input.display_name as string | undefined, repo_url: input.repo_url as string | undefined };
}

export async function resolveProject(db: D1Database, input: ProjectInput, agentId: string, source: AliasSource = 'explicit', retries = 2): Promise<Resolution> {
  const aliases = [...new Set([input.slug, ...input.aliases])];
  const placeholders = aliases.map(() => '?').join(', ');
  const matches = await db.prepare(`SELECT DISTINCT p.id, p.slug FROM projects p JOIN project_aliases a ON a.project_id = p.id WHERE a.alias IN (${placeholders})`)
    .bind(...aliases).all<Project>();
  if (matches.results.length > 1) return { ok: false, error: 'project aliases refer to different projects' };
  const slug = projectSlug(input.slug);
  const existing = matches.results[0] ?? await db.prepare('SELECT id, slug FROM projects WHERE slug = ?').bind(slug).first<Project>();
  const project = existing ?? { id: crypto.randomUUID() as ProjectId, slug };
  try {
    await persistProject(db, project, input, aliases, agentId, source, !!existing);
  } catch (error) {
    if (error instanceof Error && /UNIQUE|NOT NULL/.test(error.message)) {
      if (retries > 0) return resolveProject(db, input, agentId, source, retries - 1);
      return { ok: false, error: 'project identity conflict; retry with consistent aliases' };
    }
    throw error;
  }
  return { ok: true, project };
}

async function persistProject(db: D1Database, project: Project, input: ProjectInput, aliases: string[], agentId: string, source: AliasSource, exists: boolean): Promise<void> {
  const statements: D1PreparedStatement[] = [];
  if (!exists) statements.push(db.prepare('INSERT INTO projects (id, slug, display_name, repo_url, created_by_agent_id) VALUES (?, ?, ?, ?, ?)')
    .bind(project.id, project.slug, input.display_name ?? input.slug, input.repo_url ?? null, agentId));
  for (const alias of aliases) statements.push(db.prepare(
    `INSERT INTO project_aliases (alias, project_id, source) VALUES (?, ?, ?)
     ON CONFLICT(alias) DO UPDATE SET project_id = CASE WHEN project_aliases.project_id = excluded.project_id THEN excluded.project_id ELSE NULL END`
  ).bind(alias, project.id, source));
  // D1 batches are atomic: an alias race rolls back the new project and all aliases.
  await db.batch(statements);
}

export async function ownsSession(db: D1Database, sessionId: string | null, agentId: string): Promise<boolean> {
  if (sessionId === null) return true;
  return !!await db.prepare('SELECT id FROM sessions WHERE id = ? AND agent_id = ?').bind(sessionId, agentId).first();
}
