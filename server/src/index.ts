// Entry point that wires the Hono app, mounts feature routers, and exports the worker.
// Exports the default Hono instance that groups message, admin, and webhook routes.
// Depends on the shared routers and Env definition.

import { Hono } from 'hono';
import type { Env } from './types';
import { adminRouter } from './routes/admin';
import { messagesRouter } from './routes/messages';
import { webhooksRouter } from './routes/webhooks';

const app = new Hono<{ Bindings: Env }>({});

app.route('/api/messages', messagesRouter);
app.route('/api', adminRouter);
app.route('/api/webhooks', webhooksRouter);

app.get('/', (c) => c.text('hiboss server'));

app.onError((err, c) => {
  console.error(err);
  return c.text('internal server error', 500);
});

export default app;
