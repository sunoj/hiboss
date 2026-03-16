// Unit tests for Telegram channel utility functions.
// Tests escapeHtml, formatTelegramAgentMessage, and isImageUrl.
// Depends on vitest.

import { describe, expect, it } from 'vitest';
import { escapeHtml, formatTelegramAgentMessage, isImageUrl } from './telegram';

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
