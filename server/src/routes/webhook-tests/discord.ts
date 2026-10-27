// Discord inbound messages, thread routing and rejected updates.
// Registers webhook cases using the shared root hooks and synthetic fixtures.

import { env } from 'cloudflare:test';
import { expect } from 'vitest';
import { returnsStatus } from '../../test-request';
import { getTestAgentId } from '../../test-helpers';
import { SELF } from 'cloudflare:test';
import { DISCORD_SECRET, discordCase, postDiscordWebhook, createdDiscord } from './support';

discordCase('creates a boss_to_agent message from discord content', async () => {
  const payload = {
    channel_id: 'test-discord-ch',
    message: {
      content: 'Hello from discord',
      channel_id: 'test-discord-ch',
      author: { id: 'author', bot: false },
    },
  };

  const data = await createdDiscord(payload);
  expect(data.agent_id).toBe(getTestAgentId());
  expect(data.channel).toBe('discord');
  expect(data.direction).toBe('boss_to_agent');
  expect(data.body).toBe('Hello from discord');
});

discordCase('strips caller-supplied answered_by from discord text metadata', async () => {
  const data = await createdDiscord({
    id: 'discord-forged-attribution',
    channel_id: 'test-discord-ch',
    answered_by: { client_id: 'forged', kind: 'macos', label: 'Forged device' },
    message: {
      id: 'discord-forged-attribution',
      content: 'Discord metadata boundary',
      channel_id: 'test-discord-ch',
      author: { id: 'author', bot: false },
    },
  });
  expect(data.metadata).toMatchObject({
    id: 'discord-forged-attribution', channel_id: 'test-discord-ch',
    message: {
      id: 'discord-forged-attribution', content: 'Discord metadata boundary',
      channel_id: 'test-discord-ch', author: { id: 'author', bot: false },
    },
    source: 'discord',
    provenance: {
      source: 'discord', signature: { status: 'unsupported' },
      authentication: { kind: 'provider_account', credential_id: 'author' },
    },
  });
  expect(data.metadata?.['answered_by']).toBeUndefined();
});

discordCase('targets the matching session when a discord thread maps to discord_thread_id', async () => {
  await env.DB.prepare(
    "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, discord_thread_id) VALUES (?, ?, ?, " +
    "'working', ?)"
  ).bind('discord-thread-session-1', getTestAgentId(), 'thread-session', 'test-discord-thread').run();

  const data = await createdDiscord({
    channel_id: 'test-discord-thread',
    message: {
      content: 'Work on the router gap-closer',
      channel_id: 'test-discord-thread',
      author: { id: 'author', bot: false },
    },
  });
  expect(data.direction).toBe('boss_to_agent');
  // Scoped to the thread's session so sibling sessions don't drain it.
  expect(data.target_session_id).toBe('discord-thread-session-1');
});

discordCase('returns 400 when channel is missing', returnsStatus(400, () =>
  postDiscordWebhook({ message: { content: 'no channel' } })));

discordCase('returns 400 when body is missing', returnsStatus(400, () =>
  postDiscordWebhook({ channel_id: 'test-discord-ch' })));

discordCase('returns 403 for unknown channel_id', returnsStatus(403, () =>
  postDiscordWebhook({ channel_id: 'unknown', message: { content: 'none' } })));

discordCase('ignores bot messages', async () => {
  const res = await postDiscordWebhook({
    message: {
      content: 'bot message',
      channel_id: 'test-discord-ch',
      author: { bot: true },
    },
  });
  expect(res.status).toBe(200);
  expect(await res.text()).toBe('ignored');
});

discordCase('returns 500 when discord webhook secret is unset', async () => {
  env.DISCORD_WEBHOOK_SECRET = undefined;

  const res = await SELF.fetch('https://test.local/api/webhooks/discord', {
    method: 'POST',
    body: JSON.stringify({
      channel_id: 'test-discord-ch',
      message: {
        content: 'Hello from discord', channel_id: 'test-discord-ch',
        author: { id: 'author', bot: false },
      },
    }),
  });

  expect(res.status).toBe(500);
  expect(await res.text()).toBe('webhook secret not configured');

  env.DISCORD_WEBHOOK_SECRET = DISCORD_SECRET;
});
