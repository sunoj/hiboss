// Canonical project inventory and profile/merge requests for the console.
// Exports ProjectRecord, listProjects and patchProject; depends on boss connection.
import type { SessionStatus } from '$lib/design/semantics';
import { ApiError, type ConnectionConfig } from './types';

export type ProjectId = string & { readonly __brand: 'ProjectId' };
export interface ProjectRecord {
  id: ProjectId;
  slug: string;
  display_name: string;
  repo_url: string | null;
  aliases: string[];
  session_count: number;
  last_seen_at: string | null;
  last_post_at: string | null;
}
export type ProjectPatch = { display_name: string } | { merge_into: ProjectId };

export async function listProjects(connection: ConnectionConfig): Promise<ProjectRecord[]> {
  const response = await fetch(`${connection.baseUrl}/api/boss/projects`, {
    headers: { Authorization: `Bearer ${connection.token}` }
  });
  if (!response.ok) throw new ApiError(response.status, await response.text());
  const body = await response.json() as { projects: ProjectRecord[] };
  return body.projects;
}

export async function patchProject(connection: ConnectionConfig, id: ProjectId, patch: ProjectPatch): Promise<void> {
  const response = await fetch(`${connection.baseUrl}/api/boss/projects/${encodeURIComponent(id)}`, {
    method: 'PATCH', headers: { Authorization: `Bearer ${connection.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(patch)
  });
  if (!response.ok) throw new ApiError(response.status, await response.text());
}

export interface SessionResponse {
	project_id?: string | null;
	project_slug?: string | null;
	id: string;
	label: string | null;
	branch: string | null;
	cwd: string | null;
	status: SessionStatus | string;
	status_text: string | null;
	agent_name: string | null;
	agent_id?: string;
	last_seen_at: string;
	started_at?: string | null;
}

export interface SessionsListResponse {
	sessions: SessionResponse[];
}
