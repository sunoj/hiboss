// Entry point that wires the Hono app, mounts feature routers, and exports the worker.
// Exports the default Hono instance that groups message, admin, and webhook routes.
// Depends on the shared routers and Env definition.

import { Hono } from 'hono';
import type { Env } from './types';
import { adminRouter } from './routes/admin';
import { agentsRouter } from './routes/agents';
import { bootstrapRouter } from './routes/bootstrap';
import { joinRouter } from './routes/join';
import { messagesRouter } from './routes/messages';
import { streamRouter } from './routes/stream';
import { groupsRouter } from './routes/groups';
import { routingRouter } from './routes/routing';
import { attachmentsRouter } from './routes/attachments';
import { discordInteractionsRouter } from './routes/discord-interactions';
import { webhooksRouter } from './routes/webhooks';
import { bossesRouter } from './routes/bosses';
import { bossApiRouter } from './routes/boss-api';
import { bossInboxRouter } from './routes/boss-inbox';
import { auditRouter } from './routes/audit';
import { sessionsRouter } from './routes/sessions';
import dashboardHtml from './dashboard.html';
import { handleScheduled } from './scheduled';
import { discordGatewayRouter } from './routes/discord-gateway-api';

const app = new Hono<{ Bindings: Env }>({});

app.route('/api/attachments', attachmentsRouter);
app.route('/api/webhooks/discord-interactions', discordInteractionsRouter);
app.route('/api/webhooks', webhooksRouter);
app.route('/api/agents', agentsRouter);
app.route('/api/messages', streamRouter);
app.route('/api/messages', messagesRouter);
app.route('/api/routing-rules', routingRouter);
app.route('/api/groups', groupsRouter);
app.route('/api/bosses', bossesRouter);
app.route('/api/boss/inbox', bossInboxRouter);
app.route('/api/boss', bossApiRouter);
app.route('/api/audit', auditRouter);
app.route('/api/sessions', sessionsRouter);
app.route('/api/join', joinRouter);
app.route('/api/bootstrap', bootstrapRouter);
app.route('/api/discord-gateway', discordGatewayRouter);
app.route('/api', adminRouter);

app.get('/dashboard', (c) => c.html(dashboardHtml));
app.get('/', (c) => c.text('hiboss server'));

app.onError((err, c) => {
  console.error(err);
  return c.text('internal server error', 500);
});

export { DiscordGateway } from './discord-gateway';

export default {
  fetch: app.fetch,
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(handleScheduled(env));
  },
};
