// Background SSE listener that streams boss messages and pushes MCP notifications.
// Connects to /api/messages/stream, parses SSE events, and calls server.sendLoggingMessage.
// Depends on HibossContext for auth and the MCP Server instance for notification dispatch.

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { HibossContext } from './context.js';
import { normalizeWhitespace, truncate } from './format.js';

type SseMessage = {
  id: string;
  body: string;
  priority?: string;
  agent_name?: string;
  created_at?: string;
};

const RECONNECT_DELAY_MS = 5_000;
const SSE_PATH = '/api/messages/stream';

export function startBackgroundListener(server: McpServer, context: HibossContext): void {
  void reconnectLoop(server, context);
}

async function reconnectLoop(server: McpServer, context: HibossContext): Promise<void> {
  while (true) {
    try {
      await connectAndStream(server, context);
    } catch {
      // Connection lost or errored — reconnect after delay
    }
    await sleep(RECONNECT_DELAY_MS);
  }
}

async function connectAndStream(server: McpServer, context: HibossContext): Promise<void> {
  const url = new URL(SSE_PATH, context.baseUrl).toString();
  const response = await fetch(url, {
    headers: { ...context.headers, Accept: 'text/event-stream' },
  });

  if (!response.ok || !response.body) {
    throw new Error(`SSE connect failed: ${response.status}`);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let eventType = '';
  let eventData = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() ?? '';

    for (const line of lines) {
      if (line.startsWith('event:')) {
        eventType = line.slice(6).trim();
      } else if (line.startsWith('data:')) {
        eventData += line.slice(5).trim();
      } else if (line === '') {
        if (eventType === 'message' && eventData) {
          await handleSseMessage(server, eventData);
        }
        eventType = '';
        eventData = '';
      }
    }
  }
}

async function handleSseMessage(server: McpServer, raw: string): Promise<void> {
  try {
    const msg: SseMessage = JSON.parse(raw);
    const body = truncate(normalizeWhitespace(msg.body), 200);
    const priority = msg.priority ?? 'normal';
    const level = priority === 'critical' || priority === 'high' ? 'warning' : 'info';
    const label = `[hiboss] New boss message (${priority}): ${body}`;

    await server.sendLoggingMessage({ level, data: label });
  } catch {
    // Malformed SSE data — skip silently
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
