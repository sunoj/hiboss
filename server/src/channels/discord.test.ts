// Unit tests for Discord channel helpers and request construction.
// Tests typing calls, embed payloads, and multipart attachment uploads.
// Depends on vitest and the global fetch/FormData implementations.

import { afterEach, describe, expect, it, vi } from 'vitest';
import { sendDiscordMessage, sendDiscordTyping } from './discord';

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('sendDiscordTyping', () => {
  it('posts typing indicators for bot-backed channels', async () => {
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);

    await sendDiscordTyping({ channel_id: 'chan-1', bot_token: 'bot-1' });

    expect(fetchMock).toHaveBeenCalledWith('https://discord.com/api/v10/channels/chan-1/typing', {
      method: 'POST',
      headers: { Authorization: 'Bot bot-1' },
    });
  });

  it('skips typing for webhook-only configs', async () => {
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);

    await sendDiscordTyping({ webhook_url: 'https://discord.test/webhook' });

    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('sendDiscordMessage', () => {
  it('uploads non-image files as multipart bot attachments', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, _init?: RequestInit) => {
      const url = String(input);
      if (url === 'https://files.test/report.pdf') {
        return new Response(new Blob(['report-body']), {
          status: 200,
          headers: { 'content-disposition': 'attachment; filename="report.pdf"' },
        });
      }
      return new Response(JSON.stringify({ id: 'msg-1' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    });
    vi.stubGlobal('fetch', fetchMock);

    const result = await sendDiscordMessage(
      { channel_id: 'chan-1', bot_token: 'bot-1' },
      'Body\nAttachment: report.pdf',
      { fileUrl: 'https://files.test/report.pdf' }
    );

    expect(result).toEqual({ messageId: 'msg-1' });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    const secondCall = fetchMock.mock.calls[1];
    expect(secondCall?.[0]).toBe('https://discord.com/api/v10/channels/chan-1/messages');
    expect(secondCall?.[1]).toBeDefined();
    const request = secondCall?.[1];
    if (!request) throw new Error('missing request init');
    expect(request.method).toBe('POST');
    expect(request.headers).toEqual({ Authorization: 'Bot bot-1' });
    expect(request.body).toBeInstanceOf(FormData);
    const body = request.body as FormData;
    expect(body.get('payload_json')).toBe('{"content":"Body\\nAttachment: report.pdf","attachments":[{"id":0,"filename":"report.pdf"}]}');
    const file = body.get('files[0]');
    expect(file).toBeInstanceOf(File);
    expect((file as File).name).toBe('report.pdf');
  });

  it('sends image embeds as JSON webhook payloads', async () => {
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => new Response(JSON.stringify({ id: 'msg-2' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }));
    vi.stubGlobal('fetch', fetchMock);

    const result = await sendDiscordMessage(
      { webhook_url: 'https://discord.test/webhook', thread_id: 'thread-1' },
      'Body',
      { embeds: [{ image: { url: 'https://files.test/photo.png' } }], username: 'agent' }
    );

    expect(result).toEqual({ messageId: 'msg-2' });
    expect(fetchMock).toHaveBeenCalledWith('https://discord.test/webhook?wait=true&thread_id=thread-1', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{"content":"Body","username":"agent","embeds":[{"image":{"url":"https://files.test/photo.png"}}]}',
    });
  });
});
