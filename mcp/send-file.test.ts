// Covers the MCP send_file helper validation and request flow.
// Exports no runtime API; this file exists only for Bun tests.
// Depends on bun:test, node:fs/promises, and the send-file helper.

import { afterEach, describe, expect, it } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { MAX_FILE_BYTES, sendFile } from './send-file.ts';

const TEST_CONFIG = { serverUrl: 'https://hiboss.test', apiKey: 'secret', sessionId: 'session-1' };
const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe('sendFile', () => {
  it('fails clearly when the file is missing', async () => {
    await expect(sendFile(TEST_CONFIG, { filePath: '/tmp/hiboss-mcp-missing.txt' })).rejects.toThrow('file not found: /tmp/hiboss-mcp-missing.txt');
  });

  it('fails before upload when the file exceeds 10MB', async () => {
    const filePath = await writeTempFile('too-large.bin', new Uint8Array(MAX_FILE_BYTES + 1));
    await expect(sendFile(TEST_CONFIG, { filePath })).rejects.toThrow(`file too large: ${filePath}`);
    await rm(filePath, { force: true });
  });

  it('surfaces upload status failures', async () => {
    const filePath = await writeTempFile('report.txt', 'hello');
    globalThis.fetch = async () => new Response('bad upload', { status: 502 });

    await expect(sendFile(TEST_CONFIG, { filePath })).rejects.toThrow('upload failed (502): bad upload');
    await rm(filePath, { force: true });
  });

  it('uploads the file and sends the message with file_url', async () => {
    const filePath = await writeTempFile('report.txt', 'hello');
    const calls: Array<{ input: RequestInfo | URL; init?: RequestInit }> = [];
    globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
      calls.push({ input, init });
      if (String(input) === 'https://hiboss.test/api/attachments/upload') {
        return jsonResponse({ url: 'https://hiboss.test/api/attachments/file-1', key: 'file-1', filename: 'report.txt' }, 201);
      }
      return jsonResponse({ id: 'msg-1' }, 201);
    };

    await expect(sendFile(TEST_CONFIG, { filePath, body: 'see attached', to: 'peer-1', priority: 'high' })).resolves.toEqual({
      messageId: 'msg-1',
      url: 'https://hiboss.test/api/attachments/file-1',
    });

    expect(calls).toHaveLength(2);
    expect(String(calls[0]?.input)).toBe('https://hiboss.test/api/attachments/upload');
    expect(calls[0]?.init?.body).toBeInstanceOf(FormData);
    expect((calls[0]?.init?.body as FormData).get('file')).toBeInstanceOf(File);
    expect(calls[1]?.init?.body).toBe(JSON.stringify({
      body: 'see attached',
      file_url: 'https://hiboss.test/api/attachments/file-1',
      priority: 'high',
      session_id: 'session-1',
      to: 'peer-1',
    }));

    await rm(filePath, { force: true });
  });
});

async function writeTempFile(name: string, data: string | Uint8Array): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), 'hiboss-mcp-'));
  const filePath = join(dir, name);
  await writeFile(filePath, data);
  return filePath;
}

function jsonResponse(value: unknown, status: number): Response {
  return new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
}
