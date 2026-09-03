// MCP helper functions for tool schemas and text formatting.
// Exports schema builders plus hiboss message/session renderers.
// Depends on MCP SDK types only for CallToolResult.

import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';

type ToolMessage = {
  id: string;
  body: string;
  agent_name?: string | null;
  agent_id?: string;
  priority?: string;
  type?: string | null;
  metadata?: Record<string, unknown> | null;
};

type ToolSession = {
  id: string;
  label?: string | null;
  status?: string | null;
  agent_name?: string | null;
};

export function formatMessage(msg: ToolMessage): string {
  const from = msg.agent_name || msg.agent_id || 'unknown';
  return `[${msg.id}] from=${from} source=${sourceLabel(msg)} priority=${msg.priority || 'normal'} type=${msg.type || 'text'}\n${msg.body}`;
}

export function formatMessageList(messages: ToolMessage[], emptyText: string): string {
  return messages.length === 0 ? emptyText : messages.map(formatMessage).join('\n\n');
}

export function formatSessionList(sessions: ToolSession[], emptyText: string): string {
  if (sessions.length === 0) return emptyText;
  return sessions.map((session) => (
    `[${session.id}] label=${session.label || '-'} status=${session.status || '-'} agent=${session.agent_name || 'unknown'}`
  )).join('\n');
}

export function latestReply<T>(replies: T[]): T | null {
  return replies.length > 0 ? replies[replies.length - 1] : null;
}

export function ok(text: string): CallToolResult {
  return { content: [{ type: 'text', text }] };
}

export function fail(text: string): CallToolResult {
  return { content: [{ type: 'text', text }], isError: true };
}

export function field(type: 'string' | 'number' | 'boolean') {
  return { type };
}

export function enumField(values: string[]) {
  return { type: 'string', enum: values };
}

export function tool(name: string, description: string, properties: Record<string, unknown>, required?: string[]) {
  return { name, description, inputSchema: { type: 'object', properties, required: required && required.length ? required : undefined } };
}

function sourceLabel(message: ToolMessage): string {
  const provenance = message.metadata?.['provenance'];
  if (!provenance || typeof provenance !== 'object' || Array.isArray(provenance)) return 'unknown';
  const record = provenance as Record<string, unknown>;
  const source = typeof record['source'] === 'string' ? record['source'] : 'unknown';
  const signature = record['signature'];
  if (!signature || typeof signature !== 'object' || Array.isArray(signature)) return source;
  const state = signature as Record<string, unknown>;
  const assurance = state['scheme'] === 'JWS-ES256' ? 'verified' : state['status'];
  return typeof assurance === 'string' ? `${source}/${assurance}` : source;
}
