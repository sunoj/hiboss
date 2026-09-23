// Covers automatic-default provenance in tool results and channel/message text.
import { describe, expect, it } from 'bun:test';
import { formatAskResult, formatMessage, formatReplyBody } from './tool-helpers';

describe('ask result provenance', () => {
  it('marks server defaults in both structured and model-visible output', () => {
    const reply = { id: 'reply-1', body: 'Approve', metadata: { auto_default: true } };
    const result = formatAskResult('ask-1', reply);
    expect(result.structuredContent).toEqual({
      message_id: 'ask-1', reply_id: 'reply-1', outcome: 'auto_default', body: 'Approve',
    });
    expect(result.content).toEqual([{ type: 'text', text: formatReplyBody(reply) }]);
    expect(formatReplyBody(reply)).toContain('[auto_default] Approve');
    expect(formatReplyBody(reply)).toContain('not a boss reply or execution authorization');
    expect(formatMessage(reply)).toContain('[auto_default]');
  });

  it('does not infer automatic selection from the answer text', () => {
    for (const metadata of [undefined, { auto_default: false }]) {
      const reply = { id: 'reply-1', body: 'Approve', metadata };
      const result = formatAskResult('ask-1', reply);
      expect(result.structuredContent?.outcome).toBe('reply');
      expect(result.content).toEqual([{ type: 'text', text: 'Approve' }]);
      expect(formatReplyBody(reply)).toBe('Approve');
    }
  });

  it('preserves the recovery ID on timeout without inventing an answer', () => {
    const result = formatAskResult('ask-1', null);
    expect(result.structuredContent).toEqual({
      message_id: 'ask-1', reply_id: null, outcome: 'timeout', body: null,
    });
    expect(result.content).toEqual([{ type: 'text', text: 'No reply before timeout. Message id: ask-1' }]);
  });
});
