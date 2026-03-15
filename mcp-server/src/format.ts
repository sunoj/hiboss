// Formatting helpers for hiboss messages and MCP responses.
// Provides consistent content, truncated summaries, and error text for tools.
// Depends on the HibossMessage shape defined in types.ts.

import { HibossMessage } from './types.js';

export function getErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

export function textResult(text: string, isError = false) {
  const payload: { content: { type: 'text'; text: string }[]; isError?: true } = {
    content: [{ type: 'text', text }],
  };
  if (isError) {
    payload.isError = true;
  }
  return payload;
}

export function summarizeMessage(message: HibossMessage): string {
  const trimmed = normalizeWhitespace(message.body);
  return `${message.id} • ${message.channel} • ${message.status} • ${truncate(trimmed, 120)}`;
}

export function normalizeWhitespace(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

export function truncate(text: string, max = 120): string {
  if (text.length <= max) {
    return text;
  }
  return `${text.slice(0, max - 1)}…`;
}

export function describeReplies(message: HibossMessage): string {
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
