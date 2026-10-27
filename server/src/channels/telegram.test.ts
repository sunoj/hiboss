// Unit tests for Telegram channel utility functions.
// Tests escapeHtml, formatTelegramAgentMessage, and isImageUrl.
// Depends on vitest.

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  editTelegramCaption,
  escapeHtml,
  formatTelegramAgentMessage,
  formatTelegramAttachmentCaption,
  isImageUrl,
  sendTelegramMediaGroup,
  sendTelegramMessage,
  sendTelegramDocument,
  sendTelegramPhoto,
} from './telegram';

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('escapeHtml', () => {
  it('returns plain text unchanged', () => {
    expect(escapeHtml('hello world')).toBe('hello world');
  });

  it('returns empty string unchanged', () => {
    expect(escapeHtml('')).toBe('');
  });

  it('escapes ampersand', () => {
    expect(escapeHtml('A & B')).toBe('A &amp; B');
  });

  it('escapes less-than', () => {
    expect(escapeHtml('a < b')).toBe('a &lt; b');
  });

  it('escapes greater-than', () => {
    expect(escapeHtml('a > b')).toBe('a &gt; b');
  });

  it('escapes all three in one string', () => {
    expect(escapeHtml('<b>Tom & Jerry</b>')).toBe('&lt;b&gt;Tom &amp; Jerry&lt;/b&gt;');
  });

  it('escapes multiple occurrences', () => {
    expect(escapeHtml('a & b & c')).toBe('a &amp; b &amp; c');
  });
});

describe('formatTelegramAgentMessage', () => {
  it('wraps agent name in bold and appends body', () => {
    expect(formatTelegramAgentMessage('bot1', 'hello')).toBe('<b>[bot1]</b> hello');
  });

  it('escapes HTML in agent name', () => {
    expect(formatTelegramAgentMessage('<script>', 'hi')).toBe('<b>[&lt;script&gt;]</b> hi');
  });

  it('escapes HTML in body', () => {
    expect(formatTelegramAgentMessage('bot', 'a < b & c > d')).toBe('<b>[bot]</b> a &lt; b &amp; c &gt; d');
  });

  it('escapes both name and body', () => {
    expect(formatTelegramAgentMessage('A&B', 'x<y')).toBe('<b>[A&amp;B]</b> x&lt;y');
  });
});

describe('formatTelegramAttachmentCaption', () => {
  it('escapes attachment captions without adding html tags', () => {
    expect(formatTelegramAttachmentCaption('A&B', 'x<y')).toBe('[A&amp;B] x&lt;y');
  });
});

describe('isImageUrl', () => {
  it('returns true for .jpg', () => {
    expect(isImageUrl('https://example.com/photo.jpg')).toBe(true);
  });

  it('returns true for .jpeg', () => {
    expect(isImageUrl('https://example.com/photo.jpeg')).toBe(true);
  });

  it('returns true for .png', () => {
    expect(isImageUrl('https://example.com/photo.png')).toBe(true);
  });

  it('returns true for .gif', () => {
    expect(isImageUrl('https://example.com/anim.gif')).toBe(true);
  });

  it('returns true for .webp', () => {
    expect(isImageUrl('https://example.com/img.webp')).toBe(true);
  });

  it('returns true for .bmp', () => {
    expect(isImageUrl('https://example.com/img.bmp')).toBe(true);
  });

  it('returns false for .pdf', () => {
    expect(isImageUrl('https://example.com/doc.pdf')).toBe(false);
  });

  it('returns false for .txt', () => {
    expect(isImageUrl('https://example.com/file.txt')).toBe(false);
  });

  it('is case insensitive', () => {
    expect(isImageUrl('https://example.com/PHOTO.JPG')).toBe(true);
    expect(isImageUrl('https://example.com/img.Png')).toBe(true);
  });

  it('detects extension before query parameters', () => {
    expect(isImageUrl('https://example.com/photo.jpg?width=100')).toBe(true);
    expect(isImageUrl('https://example.com/file.pdf?v=2')).toBe(false);
  });

  it('returns false when no extension', () => {
    expect(isImageUrl('https://example.com/image')).toBe(false);
  });
});

describe('editTelegramCaption', () => {
  it('uses Telegram editMessageCaption', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await editTelegramCaption({ bot_token: 'tg-token', chat_id: 'chat-1' }, 42, '[agent] update');

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe('https://api.telegram.org/bottg-token/editMessageCaption');
    expect(JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body))).toMatchObject({
      chat_id: 'chat-1',
      message_id: 42,
      caption: '[agent] update',
      parse_mode: 'HTML',
    });
  });
});

describe('option media delivery', () => {
  it('keeps the inline keyboard on a single photo', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: 17 } }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await expect(sendTelegramPhoto(
      { bot_token: 'tg-token', chat_id: 'chat-1' },
      'https://files.test/a.png',
      'A · before',
      { inlineKeyboard: [[{ text: 'before', callback_data: 'pick-before' }]] },
    )).resolves.toBe(17);

    const payload = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body)) as Record<string, unknown>;
    expect(payload.reply_markup).toEqual({ inline_keyboard: [[{ text: 'before', callback_data: 'pick-before' }]] });
  });

  it('sends option images as a media group', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: [{ message_id: 18 }, { message_id: 19 }] }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await expect(sendTelegramMediaGroup(
      { bot_token: 'tg-token', chat_id: 'chat-1' },
      [{ url: 'https://files.test/a.png', caption: 'A · before' }, { url: 'https://files.test/b.png', caption: 'B · after' }],
    )).resolves.toEqual([18, 19]);

    const payload = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body)) as { media: { caption: string }[] };
    expect(payload.media.map((item) => item.caption)).toEqual(['A · before', 'B · after']);
  });
});

describe('send payloads and fallbacks', () => {
  const config = { bot_token: 'tg:token', chat_id: 'chat-1', message_thread_id: 4 };
  const keyboard = [[{ text: 'Choose', callback_data: 'pick' }]];
  const senders = ['message', 'photo', 'document'] as const;
  it.each(senders)('preserves %s routing and malformed-response handling', async (kind) => {
    const fetchMock = vi.fn().mockImplementation(async () => new Response('invalid json'));
    vi.stubGlobal('fetch', fetchMock);
    const options = { messageThreadId: 7, replyToMessageId: 9, inlineKeyboard: keyboard };
    const result = kind === 'message'
      ? await sendTelegramMessage(config, 'body', options)
      : await (kind === 'photo' ? sendTelegramPhoto : sendTelegramDocument)(
        config, 'https://files.test/a', '', options,
      );
    expect(result).toBeUndefined();
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[0][0]).toBe('https://api.telegram.org/bottg%3Atoken/sendChatAction');
    const request = fetchMock.mock.calls[1][1] as RequestInit;
    expect(request).toMatchObject({ method: 'POST', headers: { 'Content-Type': 'application/json' } });
    expect(JSON.parse(String(request.body))).toEqual({
      chat_id: 'chat-1', message_thread_id: 7, reply_parameters: { message_id: 9 },
      reply_markup: { inline_keyboard: keyboard },
      ...(kind === 'message' ? { text: 'body', parse_mode: 'HTML' } : { [kind]: 'https://files.test/a' }),
    });
  });

  const fallbackSenders = ['message', 'document'] as const;
  it.each(fallbackSenders)('keeps routing when %s falls back to plain text', async (kind) => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response('{}'))
      .mockResolvedValueOnce(new Response("can't parse entities", { status: 400 }))
      .mockResolvedValueOnce(new Response('{"result":{"message_id":42}}'));
    vi.stubGlobal('fetch', fetchMock);
    const options = { replyToMessageId: 9, inlineKeyboard: keyboard };
    const result = kind === 'message'
      ? await sendTelegramMessage(config, '<b>A &amp; B</b>', options)
      : await sendTelegramDocument(config, 'https://files.test/a.pdf', '<b>A &amp; B</b>', options);
    expect(result).toBe(42);
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(fetchMock.mock.calls[2][0]).toBe('https://api.telegram.org/bottg%3Atoken/sendMessage');
    expect(JSON.parse(String(fetchMock.mock.calls[2][1].body))).toEqual({
      chat_id: 'chat-1', message_thread_id: 4, reply_parameters: { message_id: 9 },
      reply_markup: { inline_keyboard: keyboard },
      text: kind === 'message' ? 'A & B' : 'A & B\n📎 https://files.test/a.pdf',
    });
  });
});

it('rejects failed photos without attempting the document text fallback', async () => {
  const fetchMock = vi.fn()
    .mockResolvedValueOnce(new Response('{}'))
    .mockResolvedValueOnce(new Response('unavailable', { status: 503 }));
  vi.stubGlobal('fetch', fetchMock);
  await expect(sendTelegramPhoto({ bot_token: 'tg-token', chat_id: 'chat-1' }, 'https://files.test/a'))
    .rejects.toThrow('telegram sendPhoto failed 503');
  expect(fetchMock).toHaveBeenCalledTimes(2);
});
