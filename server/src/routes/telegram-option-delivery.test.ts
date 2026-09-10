// Tests Telegram option-media composition and keyboard message identity.
// Depends on the delivery helper and mocked global Telegram HTTP requests.

import { afterEach, describe, expect, it, vi } from 'vitest';
import { deliverToChannelWithOptions } from './delivery';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('Telegram option-media delivery', () => {
  it('sends one option photo before the keyboard text message', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: 31 } }), { status: 200 }))
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: 32 } }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const result = await deliverToChannelWithOptions(
      'telegram',
      { chat_id: 'chat-1', bot_token: 'tg-token' },
      'agent',
      'Choose an image',
      [[{ text: 'after', callback_data: 'pick-after' }]],
      undefined,
      undefined,
      undefined,
      undefined,
      [{ label: 'after', url: 'https://files.test/after.png' }],
      ['after'],
    );

    expect(result).toEqual({ delivered: true, telegramMessageId: 32 });
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
      'https://api.telegram.org/bottg-token/sendChatAction',
      'https://api.telegram.org/bottg-token/sendPhoto',
      'https://api.telegram.org/bottg-token/sendChatAction',
      'https://api.telegram.org/bottg-token/sendMessage',
    ]);
    const photoPayload = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body)) as Record<string, unknown>;
    expect(photoPayload.caption).toBe('A · after');
    expect(photoPayload.caption).not.toContain('Choose an image');
    const textPayload = JSON.parse(String(fetchMock.mock.calls[3]?.[1]?.body)) as Record<string, unknown>;
    expect(textPayload.text).toBe('<b>[agent]</b> Choose an image');
    expect(textPayload.reply_markup).toEqual({ inline_keyboard: [[{ text: 'after', callback_data: 'pick-after' }]] });
  });

  it('sends an option album before one keyboard text message and returns its id', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: [{ message_id: 11 }, { message_id: 12 }] }), { status: 200 }))
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: 99 } }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const result = await deliverToChannelWithOptions(
      'telegram',
      { chat_id: 'chat-1', bot_token: 'tg-token' },
      'agent',
      'Choose an image',
      [[{ text: 'after', callback_data: 'pick-after' }], [{ text: 'before', callback_data: 'pick-before' }]],
      undefined,
      undefined,
      undefined,
      undefined,
      [
        { label: 'before', url: 'https://files.test/before.png' },
        { label: 'after', url: 'https://files.test/after.png', caption: 'new copy' },
      ],
      ['after', 'before'],
    );

    expect(result).toEqual({ delivered: true, telegramMessageId: 99 });
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
      'https://api.telegram.org/bottg-token/sendChatAction',
      'https://api.telegram.org/bottg-token/sendMediaGroup',
      'https://api.telegram.org/bottg-token/sendChatAction',
      'https://api.telegram.org/bottg-token/sendMessage',
    ]);
    const mediaPayload = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body)) as {
      media: { media: string; caption: string }[];
    };
    expect(mediaPayload.media).toEqual([
      { type: 'photo', media: 'https://files.test/after.png', caption: 'A · after\nnew copy', parse_mode: 'HTML' },
      { type: 'photo', media: 'https://files.test/before.png', caption: 'B · before', parse_mode: 'HTML' },
    ]);
    expect(mediaPayload.media.map((item) => item.caption).join(' ')).not.toContain('Choose an image');
    const textPayload = JSON.parse(String(fetchMock.mock.calls[3]?.[1]?.body)) as Record<string, unknown>;
    expect(textPayload.text).toBe('<b>[agent]</b> Choose an image');
    expect(textPayload.reply_markup).toEqual({
      inline_keyboard: [[{ text: 'after', callback_data: 'pick-after' }], [{ text: 'before', callback_data: 'pick-before' }]],
    });
  });

  it('sends a document before one keyboard text message for non-image media', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: 21 } }), { status: 200 }))
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: 22 } }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const result = await deliverToChannelWithOptions(
      'telegram',
      { chat_id: 'chat-1', bot_token: 'tg-token' },
      'agent',
      'Choose a file',
      [[{ text: 'approve', callback_data: 'pick-approve' }]],
      'https://files.test/report.pdf',
    );

    expect(result).toEqual({ delivered: true, telegramMessageId: 22 });
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
      'https://api.telegram.org/bottg-token/sendChatAction',
      'https://api.telegram.org/bottg-token/sendDocument',
      'https://api.telegram.org/bottg-token/sendChatAction',
      'https://api.telegram.org/bottg-token/sendMessage',
    ]);
    const documentPayload = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body)) as Record<string, unknown>;
    expect(documentPayload.caption).toBeUndefined();
    expect(documentPayload.reply_markup).toBeUndefined();
    const textPayload = JSON.parse(String(fetchMock.mock.calls[3]?.[1]?.body)) as Record<string, unknown>;
    expect(textPayload.reply_markup).toEqual({ inline_keyboard: [[{ text: 'approve', callback_data: 'pick-approve' }]] });
  });
});
