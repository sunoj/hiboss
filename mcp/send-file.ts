// Handles MCP send_file local file validation, upload, and message send.
// Exports the sendFile flow plus the max file size constant for tests.
// Depends on Bun.file, native fetch/FormData, and node:path.

import { basename } from 'node:path';

export const MAX_FILE_BYTES = 10 * 1024 * 1024;

type SendFileConfig = {
  serverUrl: string;
  apiKey: string;
  sessionId: string;
};

type SendFileInput = {
  filePath: string;
  body?: string;
  to?: string;
  priority?: string;
};

type UploadResponse = {
  url: string;
  key: string;
  filename: string;
};

type MessageResponse = {
  id: string;
};

type LocalFile = {
  blob: Blob;
  filename: string;
};

export async function sendFile(config: SendFileConfig, input: SendFileInput): Promise<{ messageId: string; url: string }> {
  const file = await readLocalFile(input.filePath);
  const upload = await uploadAttachment(config, file);
  const message = await sendAttachmentMessage(config, input, upload);
  return { messageId: message.id, url: upload.url };
}

async function readLocalFile(filePath: string): Promise<LocalFile> {
  const file = Bun.file(filePath);
  if (!await file.exists()) throw new Error(`file not found: ${filePath}`);
  if (file.size > MAX_FILE_BYTES) throw new Error(`file too large: ${filePath} (${file.size} bytes, max ${MAX_FILE_BYTES} bytes)`);
  return { blob: file, filename: basename(filePath) || 'upload' };
}

async function uploadAttachment(config: SendFileConfig, file: LocalFile): Promise<UploadResponse> {
  const form = new FormData();
  form.append('file', file.blob, file.filename);
  const response = await fetch(new URL('/api/attachments/upload', config.serverUrl), { method: 'POST', headers: authHeaders(config.apiKey), body: form });
  if (!response.ok) throw new Error(`upload failed (${response.status}): ${await response.text()}`);
  const payload = parseJson<Partial<UploadResponse>>(await response.text(), 'upload failed');
  if (!payload.url || !payload.key || !payload.filename) throw new Error('upload failed: invalid response');
  return { url: payload.url, key: payload.key, filename: payload.filename };
}

async function sendAttachmentMessage(config: SendFileConfig, input: SendFileInput, upload: UploadResponse): Promise<MessageResponse> {
  const payload = compact({
    body: input.body?.trim() || `File: ${upload.filename}`,
    file_url: upload.url,
    priority: input.priority?.trim() || undefined,
    session_id: config.sessionId,
    to: input.to?.trim() || undefined,
  });
  const response = await fetch(new URL('/api/messages', config.serverUrl), {
    method: 'POST',
    headers: authHeaders(config.apiKey, { 'Content-Type': 'application/json' }),
    body: JSON.stringify(payload),
  });
  if (!response.ok) throw new Error(`send failed (${response.status}): ${await response.text()}`);
  const message = parseJson<Partial<MessageResponse>>(await response.text(), 'send failed');
  if (!message.id) throw new Error('send failed: invalid response');
  return { id: message.id };
}

function authHeaders(apiKey: string, extra?: Record<string, string>): Record<string, string> {
  return { Authorization: `Bearer ${apiKey}`, ...extra };
}

function compact<T extends Record<string, string | undefined>>(value: T): T {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined)) as T;
}

function parseJson<T>(text: string, context: string): T {
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new Error(`${context}: invalid JSON response`);
  }
}
