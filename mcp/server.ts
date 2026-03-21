#!/usr/bin/env bun
// Bridges Claude Code MCP stdio with the hiboss REST + SSE server.
// Exports a single MCP server with hiboss tools and Claude channel notifications.
// Depends on @modelcontextprotocol/sdk, native fetch, and Node-compatible fs/process APIs.

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema, type CallToolResult, type Notification, type Request } from '@modelcontextprotocol/sdk/types.js';

type Config = { server_url: string; api_key: string; agent_name?: string };
type FileConfig = Partial<Config> & { server?: string; key?: string };
type Message = { id: string; body: string; direction: string; priority?: string; type?: string | null; reply_to?: string | null; agent_name?: string | null; agent_id?: string; status?: string; replies?: Message[] };
type MessageList = { messages?: Message[] };
type Session = { id: string };
type ClaudeChannelNotification = Notification & { method: 'notifications/claude/channel'; params: { content: string; meta: { source: 'hiboss'; message_id: string; direction: string; from: string; priority?: string; type?: string | null; reply_to?: string | null } } };

const VERSION = '1.3.0';
const INSTRUCTIONS = [
  'Messages from your boss arrive as <channel source="hiboss" message_id="..." from="..." priority="...">.',
  'Reply using the reply tool with the message_id. Use send for new outbound messages.',
  'Use ask (with options) when you need boss input - it blocks until reply or timeout.',
  "For peer agents, use send with the 'to' parameter.",
  'Never stop without asking boss for next direction via the ask tool.',
].join('\n');
const TOOL_DEFS = [
  tool('send', 'Send a new hiboss message.', { body: field('string'), to: field('string'), priority: enumField(['critical', 'high', 'normal', 'low']), options: field('string') }, ['body']),
  tool('ask', 'Ask boss for input and block until reply or timeout.', { body: field('string'), options: field('string'), timeout: field('number') }, ['body']),
  tool('reply', 'Reply to an existing hiboss message.', { message_id: field('string'), body: field('string') }, ['message_id', 'body']),
  tool('react', 'Add a reaction to a hiboss message.', { message_id: field('string'), emoji: field('string') }, ['message_id', 'emoji']),
  tool('inbox', 'List unread boss messages.', { unread: field('boolean'), limit: field('number') }),
  tool('edit_message', 'Edit the body of a previously sent message.', { message_id: field('string'), body: field('string') }, ['message_id', 'body']),
];

let state: { config: Config; session: Session; mcp: Server<Request, ClaudeChannelNotification>; stopping: boolean; shutdownTimer?: ReturnType<typeof setTimeout>; sseAbort?: AbortController } | null = null;

async function main(): Promise<void> {
  const config = loadConfig();
  const session = await registerSession(config);
  const mcp = new Server<Request, ClaudeChannelNotification>({ name: 'hiboss', version: VERSION }, { capabilities: { tools: {}, experimental: { 'claude/channel': {} } }, instructions: INSTRUCTIONS });
  const transport = new StdioServerTransport();
  state = { config, session, mcp, stopping: false };
  installHandlers(mcp);
  installProcessHandlers(mcp);
  transport.onclose = () => void shutdown('transport closed');
  await mcp.connect(transport);
  void sseLoop();
}

function installHandlers(mcp: Server<Request, ClaudeChannelNotification>): void {
  mcp.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOL_DEFS }));
  mcp.setRequestHandler(CallToolRequestSchema, async (request) => {
    try {
      return await callTool(request.params.name, request.params.arguments ?? {});
    } catch (error) {
      return fail(errorMessage(error));
    }
  });
}

function installProcessHandlers(mcp: Server<Request, ClaudeChannelNotification>): void {
  process.stdin.on('end', () => void shutdown('stdin eof'));
  process.stdin.on('close', () => void shutdown('stdin close'));
  process.on('SIGINT', () => void shutdown('sigint'));
  process.on('SIGTERM', () => void shutdown('sigterm'));
  process.on('unhandledRejection', (error) => log(`unhandledRejection: ${errorMessage(error)}`));
  process.on('uncaughtException', (error) => log(`uncaughtException: ${errorMessage(error)}`));
  mcp.oninitialized = () => log(`session ${mustState().session.id} ready`);
}

async function callTool(name: string, args: Record<string, unknown>): Promise<CallToolResult> {
  if (!state) throw new Error('server not initialized');
  if (name === 'send') return sendTool(args);
  if (name === 'ask') return askTool(args);
  if (name === 'reply') return replyTool(args);
  if (name === 'react') return reactTool(args);
  if (name === 'inbox') return inboxTool(args);
  if (name === 'edit_message') return editMessageTool(args);
  return fail(`Unknown tool: ${name}`);
}

async function sendTool(args: Record<string, unknown>): Promise<CallToolResult> {
  const payload = { body: str(args.body, 'body'), to: optStr(args.to), priority: optStr(args.priority), options: splitOptions(args.options), session_id: mustState().session.id };
  const message = await api('POST', '/api/messages', compact(payload)) as Message;
  return ok(`Sent ${message.id}.`);
}

async function askTool(args: Record<string, unknown>): Promise<CallToolResult> {
  const timeout = intOr(args.timeout, 300);
  const created = await api('POST', '/api/messages', compact({ body: str(args.body, 'body'), mode: 'blocking', options: splitOptions(args.options), session_id: mustState().session.id })) as Message;
  const polled = await api('POST', `/api/messages/${encodeURIComponent(created.id)}/poll?timeout=${timeout}`) as Message;
  const reply = latestReply(polled);
  return ok(reply ? reply.body : `No reply before timeout. Message id: ${created.id}`);
}

async function replyTool(args: Record<string, unknown>): Promise<CallToolResult> {
  const id = str(args.message_id, 'message_id');
  const message = await api('POST', `/api/messages/${encodeURIComponent(id)}/reply`, { body: str(args.body, 'body') }) as Message;
  return ok(`Replied with ${message.id}.`);
}

async function reactTool(args: Record<string, unknown>): Promise<CallToolResult> {
  const id = str(args.message_id, 'message_id');
  await api('POST', `/api/messages/${encodeURIComponent(id)}/react`, { emoji: str(args.emoji, 'emoji') });
  return ok(`Reacted to ${id}.`);
}

async function inboxTool(args: Record<string, unknown>): Promise<CallToolResult> {
  const unread = boolOr(args.unread, true);
  const limit = intOr(args.limit, 10);
  const data = await api('GET', `/api/messages?unread=${unread}&direction=boss_to_agent&limit=${limit}`) as MessageList;
  const messages = data.messages ?? [];
  return ok(messages.length === 0 ? 'Inbox is empty.' : messages.map(formatMessage).join('\n\n'));
}

async function editMessageTool(args: Record<string, unknown>): Promise<CallToolResult> {
  const id = str(args.message_id, 'message_id');
  const message = await api('PATCH', `/api/messages/${encodeURIComponent(id)}`, { body: str(args.body, 'body') }) as Message;
  return ok(`Updated ${message.id}.`);
}

async function sseLoop(): Promise<void> {
  let backoff = 1000;
  while (state && !state.stopping) {
    const controller = new AbortController();
    state.sseAbort = controller;
    try {
      await streamMessages(controller);
      backoff = 1000;
    } catch (error) {
      if (!mustState().stopping) log(`sse error: ${errorMessage(error)}`);
    }
    if (mustState().stopping) break;
    await sleep(backoff);
    backoff = Math.min(backoff * 2, 30000);
  }
}

async function streamMessages(controller: AbortController): Promise<void> {
  const { config, session, mcp } = mustState();
  const url = new URL('/api/messages/stream', config.server_url);
  url.searchParams.set('session', session.id);
  const response = await fetch(url, { headers: authHeaders(config, { Accept: 'text/event-stream' }), signal: controller.signal });
  if (!response.ok || !response.body) throw new Error(`SSE connect failed: ${response.status}`);
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let event = '';
  let data = '';
  while (!mustState().stopping) {
    const chunk = await reader.read();
    if (chunk.done) break;
    buffer += decoder.decode(chunk.value, { stream: true });
    ({ buffer, event, data } = await parseEvents(buffer, event, data, async (raw) => {
      const msg = JSON.parse(raw) as Message;
      await forwardMessage(mcp, msg);
    }));
  }
}

async function parseEvents(buffer: string, event: string, data: string, onMessage: (raw: string) => Promise<void>): Promise<{ buffer: string; event: string; data: string }> {
  const lines = buffer.split('\n');
  buffer = lines.pop() ?? '';
  for (const line of lines) {
    if (line.startsWith('event:')) event = line.slice(6).trim();
    else if (line.startsWith('data:')) data += line.slice(5).trim();
    else if (line === '') {
      if (event === 'message' && data) await onMessage(data);
      event = '';
      data = '';
    }
  }
  return { buffer, event, data };
}

async function forwardMessage(mcp: Server<Request, ClaudeChannelNotification>, msg: Message): Promise<void> {
  await mcp.notification({ method: 'notifications/claude/channel', params: { content: msg.body, meta: { source: 'hiboss', message_id: msg.id, direction: msg.direction, from: msg.agent_name || msg.agent_id || 'unknown', priority: msg.priority, type: msg.type, reply_to: msg.reply_to } } });
  try {
    await api('PATCH', `/api/messages/${encodeURIComponent(msg.id)}`, { status: 'delivered' });
  } catch (error) {
    if (!errorMessage(error).includes('delivered')) log(`deliver ack failed for ${msg.id}: ${errorMessage(error)}`);
  }
}

async function api(method: string, path: string, body?: unknown): Promise<unknown> {
  const { config } = mustState();
  const response = await fetch(new URL(path, config.server_url), { method, headers: authHeaders(config, body ? { 'Content-Type': 'application/json' } : undefined), body: body === undefined ? undefined : JSON.stringify(body) });
  if (!response.ok) throw new Error(`${method} ${path} failed: ${response.status} ${await response.text()}`);
  const text = await response.text();
  if (!text) return null;
  try { return JSON.parse(text) as unknown; } catch { return text; }
}

function loadConfig(): Config {
  const envUrl = process.env.HIBOSS_SERVER_URL?.trim();
  const envKey = process.env.HIBOSS_API_KEY?.trim();
  const file = readJson(join(homedir(), '.config', 'hiboss', 'config.json'));
  const server_url = envUrl || file.server_url || file.server || '';
  const api_key = envKey || file.api_key || file.key || '';
  if (!server_url || !api_key) throw new Error('hiboss config missing server_url/api_key (or HIBOSS_SERVER_URL/HIBOSS_API_KEY)');
  return { server_url, api_key, agent_name: file.agent_name };
}

async function registerSession(config: Config): Promise<Session> {
  const id = randomUUID();
  const label = process.env.SESSION_LABEL?.trim() || `claude-${process.pid}-${Date.now().toString(36)}`;
  const response = await fetch(new URL('/api/sessions', config.server_url), { method: 'POST', headers: authHeaders(config, { 'Content-Type': 'application/json' }), body: JSON.stringify({ id, label, cwd: process.cwd(), status: 'working' }) });
  if (!response.ok) throw new Error(`session register failed: ${response.status} ${await response.text()}`);
  return { id };
}

async function shutdown(reason: string): Promise<void> {
  if (!state || state.stopping) return;
  state.stopping = true;
  log(`shutdown: ${reason}`);
  state.shutdownTimer = setTimeout(() => process.exit(0), 2000);
  state.sseAbort?.abort();
  await Promise.allSettled([api('DELETE', `/api/sessions/${encodeURIComponent(state.session.id)}`).catch(() => null), state.mcp.close().catch(() => null)]);
  clearTimeout(state.shutdownTimer);
  process.exit(0);
}

function formatMessage(msg: Message): string {
  const from = msg.agent_name || msg.agent_id || 'unknown';
  return `[${msg.id}] from=${from} priority=${msg.priority || 'normal'} type=${msg.type || 'text'}\n${msg.body}`;
}

function latestReply(message: Message): Message | null {
  const replies = message.replies ?? [];
  return replies.length > 0 ? replies[replies.length - 1] : null;
}

function readJson(path: string): FileConfig {
  try { return JSON.parse(readFileSync(path, 'utf8')) as FileConfig; } catch { return {}; }
}

function authHeaders(config: Config, extra?: Record<string, string>): Record<string, string> {
  return { Authorization: `Bearer ${config.api_key}`, ...extra };
}

function compact<T extends Record<string, unknown>>(value: T): T {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined)) as T;
}

function str(value: unknown, name: string): string {
  if (typeof value === 'string' && value.trim()) return value.trim();
  throw new Error(`${name} is required`);
}

function optStr(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

function splitOptions(value: unknown): string[] | undefined {
  const text = optStr(value);
  return text ? text.split(',').map((item) => item.trim()).filter(Boolean) : undefined;
}

function intOr(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(1, Math.trunc(value)) : fallback;
}
function boolOr(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}
function ok(text: string): CallToolResult {
  return { content: [{ type: 'text', text }] };
}
function fail(text: string): CallToolResult {
  return { content: [{ type: 'text', text }], isError: true };
}
function mustState(): NonNullable<typeof state> {
  if (!state) throw new Error('server state unavailable');
  return state;
}
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
function log(message: string): void {
  process.stderr.write(`[hiboss-mcp] ${message}\n`);
}
function field(type: 'string' | 'number' | 'boolean') {
  return { type };
}
function enumField(values: string[]) {
  return { type: 'string', enum: values };
}
function tool(name: string, description: string, properties: Record<string, unknown>, required?: string[]) {
  return { name, description, inputSchema: { type: 'object', properties, required: required && required.length ? required : undefined } };
}

main().catch((error) => {
  log(`startup failed: ${errorMessage(error)}`);
  process.exit(1);
});
