// Unit tests for Discord channel helpers and request construction.
// Tests typing calls, embed payloads, and multipart attachment uploads.
// Depends on vitest and the global fetch/FormData implementations.
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { R2Bucket } from '@cloudflare/workers-types';
import { sendDiscordMessage, sendDiscordTyping } from './discord';

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

function mockFetch(id = 'msg-1'): ReturnType<typeof vi.fn<typeof fetch>> {
  const mock = vi.fn<typeof fetch>().mockImplementation(async () => Response.json({ id }));
  vi.stubGlobal('fetch', mock);
  return mock;
}

describe('sendDiscordTyping', () => {
  it('posts typing indicators for bot-backed channels', async () => {
    const fetchMock = mockFetch().mockResolvedValueOnce(new Response(null, { status: 204 }));
    await sendDiscordTyping({ channel_id: 'chan-1', bot_token: 'bot-1' });
    expect(fetchMock).toHaveBeenCalledExactlyOnceWith('https://discord.com/api/v10/channels/chan-1/typing', {
      method: 'POST', headers: { Authorization: 'Bot bot-1' },
    });
  });

  it('skips typing for webhook-only configs', async () => {
    const fetchMock = mockFetch().mockResolvedValueOnce(new Response(null, { status: 204 }));
    await sendDiscordTyping({ webhook_url: 'https://discord.test/webhook' });
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

function registerAttachmentCases(): void {
  it.each([
    ['uploads non-image files as multipart bot attachments', false, 'msg-1', 'Body\nAttachment: report.pdf'],
    ['reads local attachments from R2 instead of fetching the worker URL', true, 'msg-3', 'Body'],
  ] as const)('%s', async (_name, local, id, content) => {
    const fetchMock = mockFetch(id);
    const get = vi.fn(async (key: string) => key === 'legacy.pdf' ? {
      arrayBuffer: async () => new TextEncoder().encode('report-body').buffer,
      httpMetadata: { contentType: 'application/pdf' }, customMetadata: { filename: 'report.pdf' },
    } : null);
    if (!local) fetchMock.mockResolvedValueOnce(new Response(new Blob(['report-body']), {
      status: 200, headers: { 'content-disposition': 'attachment; filename="report.pdf"' },
    }));
    const send = () => sendDiscordMessage({ channel_id: 'chan-1', bot_token: 'bot-1' }, content, {
      fileUrl: local ? 'https://test.local/api/attachments/legacy.pdf' : 'https://files.test/report.pdf',
      ...(local ? { attachmentBucket: { get } as unknown as R2Bucket } : {}),
    });
    expect(await send()).toEqual({ messageId: id });
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual(local
      ? ['https://discord.com/api/v10/channels/chan-1/messages']
      : ['https://files.test/report.pdf', 'https://discord.com/api/v10/channels/chan-1/messages']);
    expect(get.mock.calls).toEqual(local ? [['legacy.pdf']] : []);
    const request = fetchMock.mock.calls.at(-1)?.[1];
    expect(request).toEqual({
      method: 'POST', headers: { Authorization: 'Bot bot-1' }, body: expect.any(FormData),
    });
    const form = request?.body as FormData;
    expect([...form.keys()]).toEqual(['payload_json', 'files[0]']);
    expect(form.get('payload_json')).toBe(JSON.stringify({
      content, attachments: [{ id: 0, filename: 'report.pdf' }],
    }));
    const file = form.get('files[0]') as File;
    expect(file).toBeInstanceOf(File);
    expect(file.name).toBe('report.pdf');
    expect(file.type).toBe(local ? 'application/pdf' : '');
    expect(await file.text()).toBe('report-body');
    fetchMock.mockClear();
    if (local) get.mockResolvedValueOnce(null);
    else fetchMock.mockResolvedValueOnce(new Response('unavailable', { status: 503 }));
    await expect(send()).rejects.toThrow(`discord attachment download failed ${local ? 404 : 503}`);
    expect(fetchMock).toHaveBeenCalledTimes(local ? 0 : 1);
  });
}

describe('sendDiscordMessage', () => {
  registerAttachmentCases();

  it('sends image embeds as JSON webhook payloads', async () => {
    const fetchMock = mockFetch('msg-2');
    const result = await sendDiscordMessage(
      { webhook_url: 'https://discord.test/webhook', thread_id: 'thread-1' }, 'Body',
      { embeds: [{ image: { url: 'https://files.test/photo.png' } }], username: 'agent' },
    );
    expect(result).toEqual({ messageId: 'msg-2' });
    expect(fetchMock).toHaveBeenCalledExactlyOnceWith(
      'https://discord.test/webhook?wait=true&thread_id=thread-1', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content: 'Body', username: 'agent',
        embeds: [{ image: { url: 'https://files.test/photo.png' } }] }),
    });
  });

  const transports = [
    ['bot', { channel_id: 'chan-1', bot_token: 'bot-1' }, 'send'],
    ['webhook', { webhook_url: 'https://discord.test/webhook' }, 'webhook'],
  ] as const;
  it.each(transports)('propagates %s HTTP and transport failures', async (_name, config, action) => {
    const fetchMock = mockFetch().mockResolvedValueOnce(new Response('denied', { status: 503 }));
    await expect(sendDiscordMessage(config, 'Body')).rejects.toThrow(`discord ${action} failed 503 denied`);
    fetchMock.mockRejectedValueOnce(new Error('offline'));
    await expect(sendDiscordMessage(config, 'Body')).rejects.toThrow('offline');
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it.each(transports)('validates %s message IDs and rejects malformed JSON', async (_name, config) => {
    const fetchMock = mockFetch();
    for (const [body, messageId] of [
      ['{}', undefined], ['{"id":5}', undefined], ['{"id":""}', ''],
    ] as const) {
      fetchMock.mockResolvedValueOnce(new Response(body));
      await expect(sendDiscordMessage(config, 'Body')).resolves.toEqual({ messageId });
    }
    fetchMock.mockResolvedValueOnce(new Response('invalid json'));
    await expect(sendDiscordMessage(config, 'Body')).rejects.toBeInstanceOf(SyntaxError);
    expect(fetchMock).toHaveBeenCalledTimes(4);
  });
});
