// Registers hiboss MCP tools and implements their handlers over the hiboss REST API.
// Exports registerTools so index.ts only wires startup + transport wiring.
// Relies on zod schemas, HTTP helpers, and formatting utilities.

import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { HibossContext } from './context.js';
import { hibossRequest, QueryParams, cleanPayload } from './http.js';
import {
  describeReplies,
  getErrorMessage,
  normalizeWhitespace,
  summarizeMessage,
  textResult,
} from './format.js';
import { HibossListResponse, HibossMessage } from './types.js';

const DEFAULT_POLL_TIMEOUT = 300;

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
    all: z.boolean().optional().describe('Return all messages instead of only unread ones.'),
    limit: z.number().int().positive().optional().describe('Maximum number of entries to return.'),
  })
  .describe('Inspect unread or recent boss messages.');

const readMessageSchema = z
  .object({ id: z.string().min(1).describe('Identifier of the boss message to inspect.') })
  .describe('Read a boss message and its replies.');

const replyMessageSchema = z
  .object({
    id: z.string().min(1).describe('Boss message identifier to reply to.'),
    body: z.string().min(1).describe('Reply text to send back to the boss.'),
  })
  .describe('Reply to a message from the boss.');

type SendResponse = HibossMessage & { reply?: HibossMessage };

export function registerTools(server: McpServer, context: HibossContext) {
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
        const response = await hibossRequest<{ id: string; status: string }>(
          context,
          'POST',
          '/api/messages',
          {
            body: cleanPayload({ body: input.body, mode: 'async', priority: input.priority, channel }),
          },
        );
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
        const post = await hibossRequest<SendResponse>(
          context,
          'POST',
          '/api/messages',
          { body: cleanPayload({ body: input.body, mode: 'blocking', channel }) },
        );
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
        const message = await hibossRequest<HibossMessage>(
          context,
          'GET',
          `/api/messages/${encodeURIComponent(input.id)}`,
        );
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
