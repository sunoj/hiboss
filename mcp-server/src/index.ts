#!/usr/bin/env node
// Starts the hiboss MCP stdio server and registers hiboss tools.
// Runs as the `hiboss-mcp` CLI, connecting hiboss APIs to MCP tools.
// Depends on @modelcontextprotocol/sdk, zod, and Node stdlib utilities.

import os from 'node:os';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

const CONFIG_PATH = path.join(os.homedir(), '.config', 'hiboss', 'config.json');
const DEFAULT_POLL_TIMEOUT = 300;
const MCP_VERSION = '0.1.0';

const sendMessageSchema = z
  .object({
    body: z.string().min(1).describe('Text to send to the boss.'),
    priority: z
      .enum(['critical', 'high', 'normal', 'low'])
      .optional()
      .describe('Message priority flag (critical/high/normal/low).'),
    channel: z
      .enum(['discord', 'telegram', 'email'])
      .optional()
      .describe('Optional delivery channel override.'),
  })
  .describe('Send an asynchronous update to the boss.');

const askBossSchema = z
  .object({
    body: z.string().min(1).describe('Question or prompt to ask the boss.'),
    timeout: z
      .number()
      .int()
      .min(1)
      .max(DEFAULT_POLL_TIMEOUT)
      .optional()
      .describe('Polling timeout in seconds (max 300).'),
    channel: z
      .enum(['discord', 'telegram', 'email'])
      .optional()
      .describe('Optional channel override for the blocking request.'),
  })
  .describe('Ask the boss and wait synchronously for a reply.');

const checkInboxSchema = z
  .object({
    all: z
      .boolean()
      .optional()
      .describe('Return all messages instead of only unread ones.'),
    limit: z
      .number()
      .int()
      .positive()
      .optional()
      .describe('Maximum number of entries to return.'),
  })
  .describe('Inspect unread or recent boss messages.');

const readMessageSchema = z
  .object({
    id: z.string().min(1).describe('Identifier of the boss message to inspect.'),
  })
  .describe('Read a boss message and its replies.');

const replyMessageSchema = z
  .object({
    id: z.string().min(1).describe('Boss message identifier to reply to.'),
    body: z.string().min(1).describe('Reply text to send back to the boss.'),
  })
  .describe('Reply to a message from the boss.');

type HibossMessage = {
  id: string;
  body: string;
  channel: string;
  status: string;
  direction: 'agent_to_boss' | 'boss_to_agent';
  mode: 'async' | 'blocking';
  priority?: string;
  reply_to: string | null;
  created_at: string;
  updated_at: string;
  replies?: HibossMessage[];
};

type HibossListResponse = { messages: HibossMessage[]; total: number };

type SendResponse = HibossMessage & { reply?: HibossMessage };

type HibossContext = {
  baseUrl: URL;
  headers: Record<string, string>;
  defaultChannel?: string;
};

async function loadHibossContext(): Promise<HibossContext> {
  const envServer = process.env.HIBOSS_SERVER;
  const envKey = process.env.HIBOSS_KEY;
  const envChannel = process.env.HIBOSS_CHANNEL;
  if (envServer && envKey) {
    return buildContext(envServer, envKey, envChannel);
  }
  const fileConfig = await readEnvFileConfig();
  if (fileConfig.server && fileConfig.key) {
    return buildContext(fileConfig.server, fileConfig.key, envChannel ?? fileConfig.channel);
  }
  throw new Error(
    'HIBOSS_SERVER and HIBOSS_KEY are not configured and no valid ~/.config/hiboss/config.json was found.',
  );
}

async function readEnvFileConfig(): Promise<{ server?: string; key?: string; channel?: string }> {
  try {
    const contents = await readFile(CONFIG_PATH, 'utf8');
    const parsed = JSON.parse(contents);
    if (parsed && typeof parsed === 'object') {
      return parsed as { server?: string; key?: string; channel?: string };
    }
    throw new Error('Config file did not parse to an object.');
  } catch (error) {
    throw new Error(`Unable to load hiboss config at ${CONFIG_PATH}: ${getErrorMessage(error)}`);
  }
}

function buildContext(server: string, key: string, channel?: string): HibossContext {
  if (!server) {
    throw new Error('Hiboss server URL is empty.');
  }
  if (!key) {
    throw new Error('Hiboss API key is empty.');
  }
  const baseUrl = new URL(server);
  return {
    baseUrl,
    headers: {
      Authorization: `Bearer ${key}`,
      Accept: 'application/json',
    },
    defaultChannel: channel,
  };
}

type QueryParams = Record<string, string | number | boolean | undefined>;

type HttpRequestOptions = {
  body?: Record<string, unknown>;
  query?: QueryParams;
};

async function hibossRequest<T>(
  context: HibossContext,
  method: 'GET' | 'POST',
  path: string,
  options: HttpRequestOptions = {},
): Promise<T> {
  const url = buildUrl(context.baseUrl, path, options.query);
  const headers: Record<string, string> = { ...context.headers };
  let body: string | undefined;
  if (options.body) {
    body = JSON.stringify(cleanPayload(options.body));
    headers['Content-Type'] = 'application/json';
  }
  const response = await fetch(url, { method, headers, body });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`status ${response.status}: ${text || '<no-response>'}`);
  }
  if (!text) {
    return {} as T;
  }
  return JSON.parse(text) as T;
}

function buildUrl(base: URL, path: string, query?: QueryParams): string {
  const url = new URL(path, base);
  if (query) {
    for (const [key, value] of Object.entries(query)) {
      if (value === undefined) {
        continue;
      }
      url.searchParams.set(key, String(value));
    }
  }
  return url.toString();
}

function cleanPayload(payload: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(payload)) {
    if (value !== undefined) {
      result[key] = value;
    }
  }
  return result;
}

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

function textResult(text: string, isError = false) {
  const payload: { content: { type: 'text'; text: string }[]; isError?: true } = {
    content: [{ type: 'text', text }],
  };
  if (isError) {
    payload.isError = true;
  }
  return payload;
}

function summarizeMessage(message: HibossMessage): string {
  const trimmed = normalizeWhitespace(message.body);
  return `${message.id} • ${message.channel} • ${message.status} • ${truncate(trimmed, 120)}`;
}

function normalizeWhitespace(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

function truncate(text: string, max = 120): string {
  if (text.length <= max) {
    return text;
  }
  return `${text.slice(0, max - 1)}…`;
}

function describeReplies(message: HibossMessage): string {
  const replies = message.replies ?? [];
  if (!replies.length) {
    return 'No replies yet.';
  }
  const lines = replies.map((reply) => {
    const summary = normalizeWhitespace(reply.body);
    return `${reply.id} replied at ${reply.updated_at}: ${truncate(summary, 140)}`;
  });
  return `Replies:\n${lines.join('\n')}`;
}

function registerTools(server: McpServer, context: HibossContext) {
  registerSendMessageTool(server, context);
  registerAskBossTool(server, context);
  registerCheckInboxTool(server, context);
  registerReadMessageTool(server, context);
  registerReplyMessageTool(server, context);
}

function registerSendMessageTool(server: McpServer, context: HibossContext) {
  server.registerTool(
    'send_message',
    {
      title: 'send_message',
      description: 'Send an asynchronous update to the boss via the hiboss API.',
      inputSchema: sendMessageSchema,
    },
    async (input) => {
      try {
        const channel = input.channel ?? context.defaultChannel;
        const payload = cleanPayload({
          body: input.body,
          mode: 'async',
          priority: input.priority,
          channel,
        });
        const response = await hibossRequest<{ id: string; status: string }>(context, 'POST', '/api/messages', {
          body: payload,
        });
        return textResult(`Message ${response.id} queued with status ${response.status}.`);
      } catch (error) {
        return textResult(`Failed to send async message: ${getErrorMessage(error)}`, true);
      }
    },
  );
}

function registerAskBossTool(server: McpServer, context: HibossContext) {
  server.registerTool(
    'ask_boss',
    {
      title: 'ask_boss',
      description: 'Post a blocking message and wait for the boss reply.',
      inputSchema: askBossSchema,
    },
    async (input) => {
      try {
        const channel = input.channel ?? context.defaultChannel;
        const post = await hibossRequest<SendResponse>(context, 'POST', '/api/messages', {
          body: cleanPayload({ body: input.body, mode: 'blocking', channel }),
        });
        const reply = post.reply ?? (await pollForReply(context, post.id, input.timeout));
        if (!reply) {
          return textResult(`No reply yet. Message id ${post.id} is pending.`);
        }
        return textResult(`Boss replied at ${reply.updated_at}: ${normalizeWhitespace(reply.body)}`);
      } catch (error) {
        return textResult(`ask_boss failed: ${getErrorMessage(error)}`, true);
      }
    },
  );
}

function registerCheckInboxTool(server: McpServer, context: HibossContext) {
  server.registerTool(
    'check_inbox',
    {
      title: 'check_inbox',
      description: 'List unread or recent boss messages.',
      inputSchema: checkInboxSchema,
    },
    async (input) => {
      try {
        const query: QueryParams = { limit: input.limit, unread: input.all ? undefined : true };
        const response = await hibossRequest<HibossListResponse>(context, 'GET', '/api/messages', { query });
        if (!response.messages.length) {
          return textResult('No matching messages found.');
        }
        const lines = response.messages.map((msg) => summarizeMessage(msg));
        return textResult(`Found ${response.messages.length} messages:\n${lines.join('\n')}`);
      } catch (error) {
        return textResult(`check_inbox failed: ${getErrorMessage(error)}`, true);
      }
    },
  );
}

function registerReadMessageTool(server: McpServer, context: HibossContext) {
  server.registerTool(
    'read_message',
    {
      title: 'read_message',
      description: 'Fetch a single message and its replies from the boss.',
      inputSchema: readMessageSchema,
    },
    async (input) => {
      try {
        const message = await hibossRequest<HibossMessage>(context, 'GET', `/api/messages/${encodeURIComponent(input.id)}`);
        const header = summarizeMessage(message);
        const replySection = describeReplies(message);
        return textResult(`${header}\n${replySection}`);
      } catch (error) {
        return textResult(`read_message failed: ${getErrorMessage(error)}`, true);
      }
    },
  );
}

function registerReplyMessageTool(server: McpServer, context: HibossContext) {
  server.registerTool(
    'reply_message',
    {
      title: 'reply_message',
      description: 'Send a reply to an existing boss message.',
      inputSchema: replyMessageSchema,
    },
    async (input) => {
      try {
        const response = await hibossRequest<HibossMessage>(
          context,
          'POST',
          `/api/messages/${encodeURIComponent(input.id)}/reply`,
          { body: { body: input.body } },
        );
        return textResult(`Reply ${response.id} queued (status ${response.status}).`);
      } catch (error) {
        return textResult(`reply_message failed: ${getErrorMessage(error)}`, true);
      }
    },
  );
}

async function pollForReply(
  context: HibossContext,
  messageId: string,
  timeout?: number,
): Promise<HibossMessage | undefined> {
  const query: QueryParams = { timeout: timeout ?? DEFAULT_POLL_TIMEOUT };
  const polled = await hibossRequest<HibossMessage>(
    context,
    'POST',
    `/api/messages/${encodeURIComponent(messageId)}/poll`,
    { query },
  );
  return getLatestReply(polled);
}

function getLatestReply(message: HibossMessage): HibossMessage | undefined {
  const replies = message.replies ?? [];
  if (!replies.length) {
    return undefined;
  }
  return replies[replies.length - 1];
}

async function main() {
  const context = await loadHibossContext();
  const server = new McpServer({ name: 'hiboss-mcp-server', version: MCP_VERSION });
  registerTools(server, context);
  const transport = new StdioServerTransport();
  transport.onclose = () => {
    void server.close();
  };
  await server.connect(transport);
}

main().catch((error) => {
  console.error('hiboss MCP server failed:', getErrorMessage(error));
  process.exit(1);
});
