// HiBoss push relay Worker: lets self-hosted servers push to opted-in app installs.
// Routes /v1/registrations and /v1/push; the cron trigger runs the purge.
// Never logs handles, secrets, tokens or ciphertext.

import { Hono } from 'hono';
import { purge } from './purge';
import { push } from './push';
import { registrations } from './registrations';
import type { AppEnv, Env } from './types';

const app = new Hono<AppEnv>();

app.use('*', async (c, next) => {
  if (new URL(c.req.url).protocol !== 'https:') {
    return c.json({ error: 'https_required' }, 403);
  }
  await next();
});

app.route('/v1/registrations', registrations);
app.route('/v1/push', push);

app.notFound((c) => c.json({ error: 'not_found' }, 404));
app.onError((_err, c) => c.json({ error: 'internal' }, 500));

export default {
  fetch: app.fetch,
  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(purge(env.DB, Date.now()));
  },
};
