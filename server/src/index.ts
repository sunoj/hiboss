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
import { bossDevicesRouter } from './routes/boss-devices';
import { auditRouter } from './routes/audit';
import { sessionsRouter } from './routes/sessions';
import dashboardHtml from './dashboard.html';
// @ts-ignore JS string module exports the service worker source.
import swJs from './sw.js';
// @ts-ignore JS string module exports the inline SVG icon markup.
import iconSvg from './icon.js';
import { handleScheduled } from './scheduled';
import { discordGatewayRouter } from './routes/discord-gateway-api';
import { requestId } from './middleware/request-id';

const app = new Hono<{ Bindings: Env; Variables: { reqId: string } }>({});
const manifest = {
  name: 'hiboss',
  short_name: 'hiboss',
  start_url: '/dashboard',
  display: 'standalone',
  background_color: '#0d1117',
  theme_color: '#161b22',
  icons: [{ src: '/icon.svg', sizes: 'any', type: 'image/svg+xml' }],
};

app.use('*', requestId);

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
app.route('/api/boss/devices', bossDevicesRouter);
app.route('/api/boss', bossApiRouter);
app.route('/api/audit', auditRouter);
app.route('/api/sessions', sessionsRouter);
app.route('/api/join', joinRouter);
app.route('/api/bootstrap', bootstrapRouter);
app.route('/api/discord-gateway', discordGatewayRouter);
app.route('/api', adminRouter);

app.get('/sw.js', (c) => c.body(swJs, { headers: { 'Content-Type': 'application/javascript; charset=utf-8', 'Cache-Control': 'no-cache' } }));
app.get('/manifest.json', (c) => c.json(manifest));
app.get('/icon.svg', (c) => c.body(iconSvg, { headers: { 'Content-Type': 'image/svg+xml; charset=utf-8' } }));
app.get('/dashboard', (c) => c.html(dashboardHtml));
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
    path: c.req.path,
    status: 500,
    message,
    name,
    stack,
  };
  console.error(JSON.stringify(payload));
  c.header('x-request-id', reqId);
  return c.json({ error: 'internal server error', request_id: reqId }, 500);
});

export { DiscordGateway } from './discord-gateway';

export default {
  fetch: app.fetch,
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(handleScheduled(env));
  },
};
