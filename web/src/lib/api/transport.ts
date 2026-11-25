// Shared authenticated HTTP transport for boss endpoints.
// Maintains the response and error behavior of the typed client.

import { DEFAULT_BASE_URL, normalizeBaseUrl } from './auth';
import { ApiError } from './types';

export class BossTransport {
	readonly baseUrl: string;
	readonly token: string;

	constructor(config: { baseUrl?: string; token: string }) {
		this.baseUrl = normalizeBaseUrl(config.baseUrl ?? DEFAULT_BASE_URL);
		this.token = config.token;
	}

	protected async request<T>(
		method: string,
		path: string,
		body?: unknown
	): Promise<T> {
		const res = await fetch(`${this.baseUrl}${path}`, {
			method,
			headers: {
				Authorization: `Bearer ${this.token}`,
				Accept: 'application/json',
				...(body !== undefined ? { 'Content-Type': 'application/json' } : {})
			},
			body: body !== undefined ? JSON.stringify(body) : undefined
		});
		const text = await res.text();
		if (!res.ok) throw new ApiError(res.status, text || res.statusText);
		if (!text) return undefined as T;
		return JSON.parse(text) as T;
	}
}
