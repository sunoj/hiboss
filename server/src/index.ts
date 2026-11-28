// Entry point that wires the Hono app, mounts feature routers, and exports the worker.
// Exports the default Hono instance that groups message, admin, and webhook routes.
// Depends on the shared routers and Env definition.

import { bossProjectsRouter } from './projects/boss-router';
import { projectAliasesRouter } from './projects/aliases-router';
import { Hono } from 'hono';
import { bossDestinationsRouter } from './routes/boss-destinations';
import { cors } from 'hono/cors';
import { matchedRoutes } from 'hono/route';
import type { Env } from './types';
import { adminRouter } from './routes/admin';
import integrationsRouter from './integrations/routes';
import discordWebhookRouter from './integrations/execute';
import { redactWebhookPath } from './integrations/credentials';
import { agentsRouter } from './routes/agents';
import { agentKeysRouter, agentSigningRouter, bossAgentKeysRouter, bossAgentSigningRouter } from './agent-keys';
import { agentBossKeysRouter } from './routes/agent-boss-keys';
import { bootstrapBossRouter } from './devices/bootstrap-boss';
import { deviceInvitesRouter } from './devices/invites';
import { joinRouter } from './routes/join';
import { messagesRouter } from './routes/messages';
import { streamRouter } from './routes/stream';
import { groupsRouter } from './routes/groups';
import { attachmentsRouter } from './routes/attachments';
import { boxRouter } from './box/items';
import { publicShares } from './box/shares/public';
import { bossesRouter } from './routes/bosses';
import { bossNotesRouter } from './routes/boss-session-notes';
import { agentNotesRouter } from './routes/session-notes';
import { bossApiRouter } from './routes/boss-api';
import { bossWritesRouter } from './routes/boss-writes';
import { bossInboxRouter } from './routes/boss-inbox';
import { bossDevicesRouter } from './routes/boss-devices';
import { auditRouter } from './routes/audit';
import { sessionsRouter } from './routes/sessions';
import { sessionEventsRouter } from './routes/session-events';
import { progressRouter } from './routes/progress';
import { progressTeamsRouter } from './routes/progress-teams';
import { handleScheduled } from './scheduled';
import { requestId } from './middleware/request-id';
import { bossPairingRouter, pairingRouter } from './routes/pairing';
import { bossSigninRouter, signinRouter } from './routes/signin';
import { bossClientsRouter } from './boss-clients';
import { bossTokensRouter } from './routes/boss-tokens';
import { bossMessageReplyRouter } from './routes/boss-message-reply';
import { bossGroupBroadcastRouter } from './routes/boss-group-broadcast';
import { repairPanelRooms } from './panels/lifecycle/repair';
import { panelLifecycleRouter } from './panels/lifecycle';
import { panelRequestsRouter, interactionRequestsRouter } from './panels/requests';
import { panelsRouter } from './panels/definition';
import { panelRelayRouter } from './panels/relay';

const app = new Hono<{ Bindings: Env; Variables: { reqId: string } }>({});
app.use('*', requestId);

// CORS for the browser-based web console and local dev. The console origin is
// deployment-specific and supplied via the CONSOLE_ORIGIN binding (exact host,
// plus its preview subdomains) so no deployment URL is hard-coded in source.
// Native clients (CLI, macOS, iOS) send no Origin and are unaffected.
app.use(
  '/api/*',
  cors({
    origin: (origin, c) => {
      if (!origin) return undefined;
      const configured = (c.env as Env).CONSOLE_ORIGIN;
      if (configured) {
        if (origin === configured) return origin;
        try {
          if (origin.endsWith('.' + new URL(configured).host)) return origin;
        } catch {
          // malformed CONSOLE_ORIGIN — fall through to localhost check
        }
      }
      if (/^http:\/\/localhost:\d+$/.test(origin)) return origin;
      return undefined;
    },
    allowHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key', 'X-Panel-Connection-Ticket'],
    allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    maxAge: 86400,
  }),
);

// Wildcard auth middleware also matches unknown paths. Return 404 before authenticating those requests.
app.use('/api/*', async (c, next) => {
  if (!matchedRoutes(c).some(route => route.method !== 'ALL')) return c.notFound();
  await next();
});

app.route('/api/attachments', attachmentsRouter);
app.route('/api/box', boxRouter);
app.route('/s', publicShares);
// Discord-compatible webhook URLs: /{17-20 digit id}/{token}.
app.route('/api/webhooks', discordWebhookRouter);
app.route('/api/:version{v[0-9]{1,2}}/webhooks', discordWebhookRouter);
app.route('/api/agents/me/keys', agentKeysRouter);
app.route('/api/agents/me/signing-keys', agentSigningRouter);
app.route('/api/agents/me/boss-keys', agentBossKeysRouter);
app.route('/api/agents', agentsRouter);
app.route('/api/integrations', integrationsRouter);
app.route('/api/messages', streamRouter);
app.route('/api/messages', messagesRouter);
app.route('/api/groups', groupsRouter);
app.route('/api/bosses', bossesRouter);
app.route('/api/boss/inbox', bossInboxRouter);
app.route('/api/boss/devices', bossDevicesRouter);
app.route('/api/boss/tokens', bossTokensRouter);
app.route('/api/boss/clients', bossClientsRouter);
app.route('/api/boss/destinations', bossDestinationsRouter);
app.route('/api/boss/projects', bossProjectsRouter);
app.route('/api/projects', projectAliasesRouter);
app.route('/api/boss', bossGroupBroadcastRouter);
app.route('/api/boss', bossWritesRouter);
app.route('/api/boss', bossMessageReplyRouter);
app.route('/api/boss/agents', bossAgentKeysRouter);
app.route('/api/boss/agents', bossAgentSigningRouter);
app.route('/api/boss', bossNotesRouter);
app.route('/api/sessions', agentNotesRouter);
app.route('/api/boss', bossApiRouter);
app.route('/api/boss/pairing', bossPairingRouter);
app.route('/api/pairing', pairingRouter);
app.route('/api/boss/signin-requests', bossSigninRouter);
app.route('/api/signin', signinRouter);
app.route('/api/audit', auditRouter);
app.route('/api/sessions', sessionsRouter);
app.route('/api/sessions', sessionEventsRouter);
app.route('/api/progress/teams', progressTeamsRouter);
app.route('/api/progress', progressRouter);
app.route('/api/panels', panelRequestsRouter);
app.route('/api/interaction-requests', interactionRequestsRouter);
app.route('/api/panels', panelLifecycleRouter);
app.route('/api/panels', panelsRouter);
app.route('/api', panelRelayRouter);
app.route('/api/join', joinRouter);
app.route('/api/devices', deviceInvitesRouter);
app.route('/api/bootstrap', bootstrapBossRouter);
app.route('/api', adminRouter);

app.get('/', (c) => c.text('hiboss server'));

app.onError((err, c) => {
  const error = err as { message?: unknown; name?: unknown; stack?: unknown } | null | undefined;
  const reqId = c.get('reqId') || crypto.randomUUID();
  const messageValue = error?.message ?? String(err);
  const message = typeof messageValue === 'string' ? messageValue : String(messageValue);
  const name = typeof error?.name === 'string' ? error.name : undefined;
  const stack = typeof error?.stack === 'string' ? error.stack : undefined;
  const payload = {
    ts: new Date().toISOString(),
    level: 'error',
    reqId,
    method: c.req.method,
    path: redactWebhookPath(c.req.path),
    status: 500,
    message,
    name,
    stack,
  };
  console.error(JSON.stringify(payload));
  c.header('x-request-id', reqId);
  return c.json({ error: 'internal server error', request_id: reqId }, 500);
});

export { PanelRoom } from './panels/relay/room';

export default {
  fetch: app.fetch,
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(handleScheduled(env));
    ctx.waitUntil(repairPanelRooms(env));
  },
};
