// Creates integration agents and manages their webhook URLs in audited D1 batches.
// Exports createIntegration, listIntegrations, addWebhook, rotateWebhook and revokeWebhook.
// Dependencies: D1, project slugs and webhook credentials; tokens are returned once, never stored.
import { projectSlug } from '../projects';
import { hashWebhookToken, newWebhookId, newWebhookToken } from './credentials';

export type PriorityCap = 'low' | 'normal' | 'high';
export interface IssuedWebhook { id: string; token: string; label: string; priority_cap: PriorityCap }
export interface CreatedIntegration { agent_id: string; name: string; session_id: string; webhook: IssuedWebhook }

/** Audits only a webhook row that exists and is live, so a no-op leaves no record. */
function audit(db: D1Database, actor: string, action: string, id: string, details: object): D1PreparedStatement {
  return db.prepare(`INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
    SELECT 'agent', ?, ?, 'agent_webhook', id, ? FROM agent_webhooks WHERE id = ? AND revoked_at IS NULL`)
    .bind(actor, action, JSON.stringify(details), id);
}

async function webhookInsert(db: D1Database, agentId: string, sessionId: string, label: string,
  cap: PriorityCap, actor: string): Promise<{ issued: IssuedWebhook; statement: D1PreparedStatement }> {
  const issued = { id: newWebhookId(), token: newWebhookToken(), label, priority_cap: cap };
  const statement = db.prepare(`INSERT INTO agent_webhooks
      (id, agent_id, session_id, token_hash, label, priority_cap, created_by_agent_id)
    SELECT ?, id, ?, ?, ?, ?, ? FROM api_keys WHERE id = ? AND kind = 'integration'`)
    .bind(issued.id, sessionId, await hashWebhookToken(issued.token), label, cap, actor, agentId);
  return { issued, statement };
}

/** The integration's own project slug never merges with a repository's project. */
function integrationSlug(name: string, agentId: string): string {
  return `webhook-${projectSlug(name).slice(0, 48) || 'integration'}-${agentId.slice(0, 6)}`;
}

/** One batch: the agent, its project, its idle session, the first URL and the audit rows. */
export async function createIntegration(db: D1Database, name: string, cap: PriorityCap,
  actor: string): Promise<CreatedIntegration | null> {
  const agentId = crypto.randomUUID().replaceAll('-', '');
  const projectId = crypto.randomUUID();
  const sessionId = crypto.randomUUID();
  const slug = integrationSlug(name, agentId);
  const { issued, statement } = await webhookInsert(db, agentId, sessionId, name, cap, actor);
  const [agents] = await db.batch<{ id: string }>([
    db.prepare(`INSERT INTO api_keys (id, name, kind) VALUES (?, ?, 'integration')
      ON CONFLICT(name) DO NOTHING RETURNING id`).bind(agentId, name),
    db.prepare(`INSERT INTO projects (id, slug, display_name, created_by_agent_id)
      SELECT ?, ?, ?, id FROM api_keys WHERE id = ?`).bind(projectId, slug, name, agentId),
    db.prepare(`INSERT INTO project_aliases (alias, project_id, source)
      SELECT ?, id, 'explicit' FROM projects WHERE id = ?`).bind(slug, projectId),
    db.prepare(`INSERT INTO sessions (id, agent_id, label, status, project_id, runtime)
      SELECT ?, id, ?, 'idle', ?, 'webhook' FROM api_keys WHERE id = ?`).bind(sessionId, slug, projectId, agentId),
    statement,
    audit(db, actor, 'integration.create', issued.id, { agent_id: agentId, name }),
  ]);
  if (!agents.results[0]) return null;
  return { agent_id: agentId, name, session_id: sessionId, webhook: issued };
}

export interface WebhookSummary {
  id: string; agent_id: string; agent_name: string; label: string; priority_cap: PriorityCap;
  created_at: string; last_used_at: string | null; revoked_at: string | null;
}

export async function listIntegrations(db: D1Database): Promise<WebhookSummary[]> {
  const rows = await db.prepare(`SELECT w.id, w.agent_id, a.name AS agent_name, w.label, w.priority_cap,
      w.created_at, w.last_used_at, w.revoked_at
    FROM agent_webhooks w JOIN api_keys a ON a.id = w.agent_id
    WHERE a.kind = 'integration' ORDER BY a.name, w.created_at DESC LIMIT 500`).all<WebhookSummary>();
  return rows.results ?? [];
}

export async function addWebhook(db: D1Database, agentId: string, label: string, cap: PriorityCap,
  actor: string): Promise<IssuedWebhook | null> {
  const session = await db.prepare(`SELECT s.id FROM sessions s JOIN api_keys a ON a.id = s.agent_id
    WHERE s.agent_id = ? AND a.kind = 'integration' LIMIT 1`).bind(agentId).first<{ id: string }>();
  if (!session) return null;
  const { issued, statement } = await webhookInsert(db, agentId, session.id, label, cap, actor);
  await db.batch([statement, audit(db, actor, 'integration.webhook.add', issued.id, { agent_id: agentId })]);
  return issued;
}

/** The old token stops working in the same statement that stores the new one. */
export async function rotateWebhook(db: D1Database, id: string, actor: string): Promise<string | null> {
  const token = newWebhookToken();
  const [updated] = await db.batch<{ id: string }>([
    db.prepare(`UPDATE agent_webhooks SET token_hash = ? WHERE id = ? AND revoked_at IS NULL RETURNING id`)
      .bind(await hashWebhookToken(token), id),
    audit(db, actor, 'integration.webhook.rotate', id, {}),
  ]);
  return updated.results[0] ? token : null;
}

export async function revokeWebhook(db: D1Database, id: string, actor: string): Promise<boolean> {
  const [, updated] = await db.batch<{ id: string }>([
    audit(db, actor, 'integration.webhook.revoke', id, {}),
    db.prepare(`UPDATE agent_webhooks SET revoked_at = datetime('now')
      WHERE id = ? AND revoked_at IS NULL RETURNING id`).bind(id),
  ]);
  return !!updated.results[0];
}
