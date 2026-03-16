// Entry point that wires the Hono app, mounts feature routers, and exports the worker.
// Exports the default Hono instance that groups message, admin, and webhook routes.
// Depends on the shared routers and Env definition.

import { Hono } from 'hono';
import type { Env } from './types';
import { adminRouter } from './routes/admin';
import { agentsRouter } from './routes/agents';
import { bootstrapRouter } from './routes/bootstrap';
import { messagesRouter } from './routes/messages';
import { streamRouter } from './routes/stream';
import { groupsRouter } from './routes/groups';
import { routingRouter } from './routes/routing';
import { attachmentsRouter } from './routes/attachments';
import { webhooksRouter } from './routes/webhooks';

const app = new Hono<{ Bindings: Env }>({});

app.route('/api/attachments', attachmentsRouter);
app.route('/api/webhooks', webhooksRouter);
app.route('/api/agents', agentsRouter);
app.route('/api/messages', streamRouter);
app.route('/api/messages', messagesRouter);
app.route('/api/routing-rules', routingRouter);
app.route('/api/groups', groupsRouter);
app.route('/api/bootstrap', bootstrapRouter);
app.route('/api', adminRouter);

app.get('/', (c) => c.text('hiboss server'));

app.onError((err, c) => {
  console.error(err);
  return c.text('internal server error', 500);
});

export default app;
