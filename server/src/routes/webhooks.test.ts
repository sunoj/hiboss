// Integration tests for /api/webhooks routes.
// Registers Telegram, Discord, command and routing cases in their original order.
// Depends on cloudflare:test and shared webhook fixtures.

import './webhook-tests/telegram-text';
import './webhook-tests/telegram-actions';
import './webhook-tests/discord';
import './webhook-tests/commands-routing';
import { beforeAll, afterEach, vi } from 'vitest';
import { seedWebhooks } from './webhook-tests/support';

beforeAll(seedWebhooks);

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});
