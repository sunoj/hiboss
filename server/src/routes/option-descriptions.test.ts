// Tests description normalization and channel fallback payloads.
// Depends on the description parser, channel delivery, and mocked fetch.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { appendOptionDescriptions, parseOptionDescriptions } from './option-descriptions';
import { deliverToChannelWithOptions } from './delivery';

afterEach(() => vi.unstubAllGlobals());

describe('option descriptions', () => {
  it('orders descriptions by offered option and counts Unicode characters', () => {
    const text = '😀'.repeat(200);
    expect(parseOptionDescriptions([{ label: ' B ', text: ` ${text} ` },
      { label: 'A', text: 'first' }], ['A', 'B'])).toEqual({ ok: true, value: [
      { label: 'A', text: 'first' }, { label: 'B', text },
    ] });
    expect(parseOptionDescriptions(undefined, undefined)).toEqual({ ok: true, value: undefined });
  });

  it('leaves bodies without valid descriptions unchanged', () => {
    expect(appendOptionDescriptions('Choose', null)).toBe('Choose');
    expect(appendOptionDescriptions('Choose', { option_descriptions: [] })).toBe('Choose');
  });

  it.each(['telegram', 'discord'] as const)('appends descriptions to %s text', async channel => {
    const fetchMock = vi.fn().mockImplementation(async () => new Response(
      JSON.stringify({ id: '42', result: { message_id: 42 } }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);
    const body = appendOptionDescriptions('Choose', {
      options: ['A', 'B'], option_descriptions: [{ label: 'B', text: '**keep**' }],
    }, channel);
    await deliverToChannelWithOptions(channel,
      channel === 'telegram' ? { chat_id: 'chat', bot_token: 'token' }
        : { webhook_url: 'https://discord.test/webhook' },
      'agent', body, [[{ text: 'B', callback_data: 'pick-B' }]]);
    const payloads = fetchMock.mock.calls.map(call => JSON.parse(String(call[1].body)) as
      { text?: string; content?: string });
    const payload = payloads.find(item => item.text || item.content);
    expect(payload?.text ?? payload?.content).toContain(channel === 'telegram'
      ? 'Choose\n\n• B — **keep**' : 'Choose\n\n• B — \\*\\*keep\\*\\*');
  });
});
