/** Typed boss-surface HTTP client (Bearer auth). */

import {
	DEFAULT_BASE_URL,
	normalizeBaseUrl,
	type StoredConnection
} from './auth';
import { normalizeMessage } from './mappers';
import {
	ApiError,
	type AgentsListResponse,
	type BossMe,
	type BossOverview,
	type ForwardRequest,
	type MessageResponse,
	type MessagesListResponse,
	type MessagesQuery,
	type ReactRequest,
	type ReplyRequest,
	type SessionsListResponse
} from './types';

export class BossApiClient {
	readonly baseUrl: string;
	readonly token: string;

	constructor(config: { baseUrl?: string; token: string }) {
		this.baseUrl = normalizeBaseUrl(config.baseUrl ?? DEFAULT_BASE_URL);
		this.token = config.token;
	}

	static fromConnection(conn: StoredConnection): BossApiClient {
		return new BossApiClient(conn);
	}

	async me(): Promise<BossMe> {
		return this.request<BossMe>('GET', '/api/boss/me');
	}

	async overview(): Promise<BossOverview> {
		return this.request<BossOverview>('GET', '/api/boss/overview');
	}

	async messages(query: MessagesQuery = {}): Promise<MessagesListResponse> {
		const params = new URLSearchParams();
		if (query.direction) params.set('direction', query.direction);
		if (query.limit != null) params.set('limit', String(query.limit));
		if (query.offset != null) params.set('offset', String(query.offset));
		if (query.priority) params.set('priority', query.priority);
		if (query.session) params.set('session', query.session);
		if (query.search) params.set('search', query.search);
		if (query.unread) params.set('unread', 'true');
		if (query.agent) params.set('agent', query.agent);
		const qs = params.toString();
		const path = qs ? `/api/boss/messages?${qs}` : '/api/boss/messages';
		const raw = await this.request<{ messages: unknown[]; total: number }>('GET', path);
		return {
			total: raw.total ?? 0,
			messages: (raw.messages ?? []).map((m) =>
				normalizeMessage(m as Record<string, unknown>)
			)
		};
	}

	async sessions(): Promise<SessionsListResponse> {
		return this.request<SessionsListResponse>('GET', '/api/boss/sessions');
	}

	async agents(): Promise<AgentsListResponse> {
		return this.request<AgentsListResponse>('GET', '/api/boss/agents');
	}

	/** Typed for later wiring — not used by Dashboard foundation. */
	async reply(messageId: string, body: ReplyRequest): Promise<MessageResponse> {
		const raw = await this.request<Record<string, unknown>>(
			'POST',
			`/api/boss/messages/${encodeURIComponent(messageId)}/reply`,
			body
		);
		return normalizeMessage(raw);
	}

	async react(messageId: string, body: ReactRequest): Promise<unknown> {
		return this.request('POST', `/api/boss/messages/${encodeURIComponent(messageId)}/react`, body);
	}

	async forward(messageId: string, body: ForwardRequest): Promise<MessageResponse> {
		const raw = await this.request<Record<string, unknown>>(
			'POST',
			`/api/boss/messages/${encodeURIComponent(messageId)}/forward`,
			body
		);
		return normalizeMessage(raw);
	}

	/** SSE URL helpers — wiring optional this task. */
	streamUrl(kind: 'options' | 'feed' = 'feed'): string {
		const q = kind === 'options' ? 'options=true' : 'feed=true';
		return `${this.baseUrl}/api/boss/stream?${q}`;
	}

	streamHeaders(): HeadersInit {
		return { Authorization: `Bearer ${this.token}`, Accept: 'text/event-stream' };
	}

	private async request<T>(
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

export async function validateConnection(
	baseUrl: string,
	token: string
): Promise<BossMe> {
	const client = new BossApiClient({ baseUrl, token });
	return client.me();
}
