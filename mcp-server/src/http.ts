// Handles HTTP requests between the MCP server and hiboss REST endpoints.
// Provides query helpers, payload cleaning, and the typed hibossRequest wrapper.
// Depends on the HibossContext for baseURL/headers and Node fetch.

import { HibossContext } from './context.js';

type QueryParams = Record<string, string | number | boolean | undefined>;

type HttpRequestOptions = {
  body?: Record<string, unknown>;
  query?: QueryParams;
};

export async function hibossRequest<T>(
  context: HibossContext,
  method: 'GET' | 'POST',
  path: string,
  options: HttpRequestOptions = {},
): Promise<T> {
  const url = buildUrl(context.baseUrl, path, options.query);
  const headers: Record<string, string> = { ...context.headers };
  let body: string | undefined;
  if (options.body) {
    body = JSON.stringify(cleanPayload(options.body));
    headers['Content-Type'] = 'application/json';
  }
  const response = await fetch(url, { method, headers, body });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`status ${response.status}: ${text || '<no-response>'}`);
  }
  if (!text) {
    return {} as T;
  }
  return JSON.parse(text) as T;
}

function buildUrl(base: URL, path: string, query?: QueryParams): string {
  const url = new URL(path, base);
  if (query) {
    for (const [key, value] of Object.entries(query)) {
      if (value === undefined) {
        continue;
      }
      url.searchParams.set(key, String(value));
    }
  }
  return url.toString();
}

export function cleanPayload(payload: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(payload)) {
    if (value !== undefined) {
      result[key] = value;
    }
  }
  return result;
}

export { QueryParams, HttpRequestOptions };
