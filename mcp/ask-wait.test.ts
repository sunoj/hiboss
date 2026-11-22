// Covers the MCP ask lifetime: a short requested timeout still gives the boss a full minute,
// and a long one is waited across several bounded poll windows.
import { describe, expect, it } from 'bun:test';
import { askTimeoutSeconds, waitForReply } from './ask-wait';

describe('ask timeout', () => {
  it('never gives the boss less than a minute', () => {
    expect(askTimeoutSeconds(15)).toBe(60);
    expect(askTimeoutSeconds(0)).toBe(60);
    expect(askTimeoutSeconds(90000)).toBe(86400);
    expect(askTimeoutSeconds(600.7)).toBe(600);
    expect(askTimeoutSeconds(undefined)).toBe(1800);
  });
});

describe('waitForReply', () => {
  it('polls bounded windows until the deadline', async () => {
    let clock = 0;
    const windows: number[] = [];
    const result = await waitForReply(async (window) => {
      windows.push(window);
      clock += window * 1000;
      return { replies: [] as string[] };
    }, (poll) => poll.replies.length > 0, 700, () => clock);
    expect(result.replies).toEqual([]);
    expect(windows).toEqual([300, 300, 100]);
  });

  it('returns as soon as a reply arrives', async () => {
    let calls = 0;
    const result = await waitForReply(async () => {
      calls += 1;
      return { replies: calls === 2 ? ['B'] : [] };
    }, (poll) => poll.replies.length > 0, 1800, () => 0);
    expect(result.replies).toEqual(['B']);
    expect(calls).toBe(2);
  });
});
