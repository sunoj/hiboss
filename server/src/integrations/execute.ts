// Discord-compatible Execute Webhook endpoint: a sender swaps discord.com for the HiBoss host.
// Exports the router mounted at /api/webhooks and /api/v{n}/webhooks for /{id}/{token}.
// Dependencies: Hono, webhook credentials, the shared send core, and the Discord payload helpers.
import { Hono, type Context } from 'hono';
import type { Env, Priority } from '../types';
import { checkRateLimit } from '../routes/message-helpers';
import { finishSend, persistSend } from '../routes/message-send';
import { selectLegacyConfigs, type SendInput } from '../routes/message-send-input';
import type { SendTarget } from '../routes/message-send-target';
import { webhookProvenance } from '../message-security/provenance';
import { findWebhook, type WebhookCredential } from './credentials';
import { INVALID_BODY, SUPPRESS_NOTIFICATIONS, type DiscordError, type DiscordPayload } from './discord-payload';
import { renderDiscordMessage } from './discord-render';
import { readWebhookBody, storeWebhookFiles, type WebhookBody } from './webhook-body';

const router = new Hono<{ Bindings: Env }>({});
const PATH = '/:id{[0-9]{17,20}}/:token{[A-Za-z0-9_-]{1,128}}';
const UNKNOWN_WEBHOOK: DiscordError = { status: 404, code: 10015, message: 'Unknown Webhook' };
const TARGET: SendTarget = { targetAgentId: null, targetSessionId: null, direction: 'agent_to_boss',
  targetWarning: null, targetSession: null };

type WebhookContext = Context<{ Bindings: Env }>;

function discordError(c: WebhookContext, error: DiscordError): Response {
  return c.json({ message: error.message, code: error.code }, error.status);
}

async function authenticate(c: WebhookContext): Promise<WebhookCredential | null> {
  return findWebhook(c.env.DB, c.req.param('id') ?? '', c.req.param('token') ?? '');
}

router.get(PATH, async (c) => {
  const credential = await authenticate(c);
  if (!credential) return discordError(c, UNKNOWN_WEBHOOK);
  return c.json({ id: credential.id, type: 1, name: credential.label, avatar: null, channel_id: null,
    guild_id: null, application_id: null, token: c.req.param('token') });
});

router.post(PATH, async (c) => {
  const body = await readWebhookBody(c.req.raw);
  if ('status' in body) return discordError(c, body);
  const credential = await authenticate(c);
  if (!credential) return discordError(c, UNKNOWN_WEBHOOK);
  if (credential.rate_limit && await checkRateLimit(c.env, credential.agent_id, credential.rate_limit)) {
    return rateLimited(c, credential);
  }
  return deliver(c, credential, body);
});

router.on(['PUT', 'PATCH', 'DELETE'], PATH, (c) =>
  discordError(c, { status: 405, code: 0, message: '405: Method Not Allowed' }));

function rateLimited(c: WebhookContext, credential: WebhookCredential): Response {
  // The window is the last minute of messages, so a minute always clears it.
  c.header('Retry-After', '60');
  c.header('X-RateLimit-Limit', String(credential.rate_limit));
  c.header('X-RateLimit-Remaining', '0');
  c.header('X-RateLimit-Reset-After', '60');
  c.header('X-RateLimit-Bucket', credential.id);
  c.header('X-RateLimit-Scope', 'user');
  return c.json({ message: 'You are being rate limited.', retry_after: 60, global: false }, 429);
}

function priorityOf(credential: WebhookCredential, payload: DiscordPayload): Priority {
  return payload.flags & SUPPRESS_NOTIFICATIONS ? 'low' : credential.priority_cap;
}

async function deliver(c: WebhookContext, credential: WebhookCredential, body: WebhookBody): Promise<Response> {
  const { payload } = body;
  const { fileUrl, fileLines } = await storeWebhookFiles(c.env, body.files, c.req.url, credential.agent_id);
  const rendered = renderDiscordMessage(payload, credential.agent_name, fileLines);
  const priority = priorityOf(credential, payload);
  const metadata: Record<string, unknown> = { content: rendered.content,
    ...webhookProvenance(credential.agent_id, credential.id) };
  if (fileUrl) metadata.file_url = fileUrl;
  if (payload.threadName) metadata.webhook = { thread_name: payload.threadName };
  const input: SendInput = {
    agentId: credential.agent_id, payload: {}, body: rendered.title, idempotencyKey: null,
    agentConfig: { default_priority: credential.priority_cap, rate_limit: credential.rate_limit,
      channel_routing: credential.channel_routing, avatar_url: credential.avatar_url },
    mode: 'async', priority, requestedChannel: undefined, fileUrl, messageType: 'text',
    sessionId: credential.session_id, toAgent: null, options: undefined,
    optionMediaResult: { ok: true, value: undefined }, metadata, clientMetadata: null, timeout: null,
    channelConfigs: await selectLegacyConfigs(c.env, credential.agent_id, priority, undefined),
    integration: true,
  };
  const inserted = await persistSend(c, input, TARGET);
  if (inserted instanceof Response) return discordError(c, { ...INVALID_BODY, message: 'Message not stored' });
  const finished = await finishSend(c, input, TARGET, inserted);
  if (finished.status >= 400) return finished;
  await touch(c.env, credential, rendered.title);
  if (!isTruthy(c.req.query('wait'))) return c.body(null, 204);
  return c.json({ id: inserted.id, type: 0, channel_id: null, content: payload.content ?? '',
    embeds: [], attachments: [], timestamp: inserted.created_at, webhook_id: credential.id,
    author: { id: credential.id, username: credential.label, bot: true } });
}

function isTruthy(value: string | undefined): boolean {
  return value === 'true' || value === 'True' || value === '1';
}

/** Shows the latest alert on the integration's session; usage is stamped at most once a minute. */
async function touch(env: Env, credential: WebhookCredential, title: string): Promise<void> {
  const statements = [env.DB.prepare(`UPDATE sessions SET status_text = ?, last_seen_at = datetime('now')
    WHERE id = ? AND agent_id = ?`).bind(title.slice(0, 100), credential.session_id, credential.agent_id)];
  const last = credential.last_used_at ? Date.parse(`${credential.last_used_at}Z`) : 0;
  if (Date.now() - last > 60_000) {
    statements.push(env.DB.prepare(`UPDATE agent_webhooks SET last_used_at = datetime('now') WHERE id = ?`)
      .bind(credential.id));
  }
  await env.DB.batch(statements);
}

export default router;
