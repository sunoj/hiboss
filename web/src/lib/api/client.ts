/** Typed boss-surface HTTP client (Bearer auth). */

import {
	DEFAULT_BASE_URL,
	normalizeBaseUrl,
	type StoredConnection
} from './auth';
import { normalizeMessage } from './mappers';
import {
	ApiError,
	type AgentConfigResponse,
	type AgentConfigUpdateRequest,
	type AgentsListResponse,
	type AuditListResponse,
	type AuditQuery,
	type BossChannelConfig,
	type BossMe,
	type BossOverview,
	type BossCreateRequest,
	type BossRecord,
	type BossSystemResponse,
	type BossesListResponse,
	type BossTokenResponse,
	type BossUpdateRequest,
	type BroadcastGroupRequest,
	type BroadcastGroupResponse,
	type CreateGroupRequest,
	type CreateRoutingRuleRequest,
	type ForwardRequest,
	type GroupMemberRequest,
	type GroupWriteResponse,
	type GroupsListResponse,
	type MessageResponse,
	type MessagesListResponse,
	type MessagesQuery,
	type OkResponse,
	type ReactRequest,
	type ReplyRequest,
	type RoutingRulesListResponse,
	type RoutingRuleResponse,
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

	async bosses(): Promise<BossesListResponse> {
		return this.request<BossesListResponse>('GET', '/api/bosses');
	}

	async createBoss(body: BossCreateRequest): Promise<BossRecord> {
		return this.request<BossRecord>('POST', '/api/bosses', body);
	}

	async updateBoss(id: string, body: BossUpdateRequest): Promise<BossRecord> {
		return this.request<BossRecord>('PATCH', `/api/bosses/${encodeURIComponent(id)}`, body);
	}

	async deleteBoss(id: string): Promise<OkResponse> {
		return this.request<OkResponse>('DELETE', `/api/bosses/${encodeURIComponent(id)}`);
	}

	async grantAccess(id: string, agentId: string): Promise<OkResponse> {
		return this.request<OkResponse>('POST', `/api/bosses/${encodeURIComponent(id)}/access`, {
			agent_id: agentId
		});
	}

	async revokeAccess(id: string, agentId: string): Promise<OkResponse> {
		return this.request<OkResponse>(
			'DELETE',
			`/api/bosses/${encodeURIComponent(id)}/access/${encodeURIComponent(agentId)}`
		);
	}

	async rotateToken(id: string): Promise<BossTokenResponse> {
		return this.request<BossTokenResponse>('POST', `/api/bosses/${encodeURIComponent(id)}/token`);
	}

	async groups(): Promise<GroupsListResponse> {
		return this.request<GroupsListResponse>('GET', '/api/boss/groups');
	}

	async createGroup(body: CreateGroupRequest): Promise<GroupWriteResponse> {
		return this.request<GroupWriteResponse>('POST', '/api/boss/groups', body);
	}

	async deleteGroup(id: string): Promise<OkResponse> {
		return this.request<OkResponse>('DELETE', `/api/boss/groups/${encodeURIComponent(id)}`);
	}

	async addGroupMember(id: string, body: GroupMemberRequest): Promise<OkResponse> {
		return this.request<OkResponse>('POST', `/api/boss/groups/${encodeURIComponent(id)}/members`, body);
	}

	async removeGroupMember(id: string, agentId: string): Promise<OkResponse> {
		return this.request<OkResponse>(
			'DELETE',
			`/api/boss/groups/${encodeURIComponent(id)}/members/${encodeURIComponent(agentId)}`
		);
	}

	async broadcastGroup(id: string, body: BroadcastGroupRequest): Promise<BroadcastGroupResponse> {
		return this.request<BroadcastGroupResponse>(
			'POST',
			`/api/boss/groups/${encodeURIComponent(id)}/broadcast`,
			body
		);
	}

	async routingRules(): Promise<RoutingRulesListResponse> {
		return this.request<RoutingRulesListResponse>('GET', '/api/boss/routing-rules');
	}

	async createRoutingRule(body: CreateRoutingRuleRequest): Promise<RoutingRuleResponse> {
		return this.request<RoutingRuleResponse>('POST', '/api/boss/routing-rules', body);
	}

	async deleteRoutingRule(id: string): Promise<OkResponse> {
		return this.request<OkResponse>('DELETE', `/api/boss/routing-rules/${encodeURIComponent(id)}`);
	}

	async updateAgentConfig(id: string, body: AgentConfigUpdateRequest): Promise<AgentConfigResponse> {
		return this.request<AgentConfigResponse>(
			'PATCH',
			`/api/boss/agents/${encodeURIComponent(id)}/config`,
			body
		);
	}

	async channels(): Promise<BossChannelConfig[]> {
		return this.request<BossChannelConfig[]>('GET', '/api/boss/channels');
	}

	async system(): Promise<BossSystemResponse> {
		return this.request<BossSystemResponse>('GET', '/api/boss/system');
	}

	async audit(query: AuditQuery = {}): Promise<AuditListResponse> {
		const params = new URLSearchParams();
		if (query.actor_type) params.set('actor_type', query.actor_type);
		if (query.action) params.set('action', query.action);
		if (query.limit != null) params.set('limit', String(query.limit));
		if (query.offset != null) params.set('offset', String(query.offset));
		const qs = params.toString();
		const path = qs ? `/api/boss/audit?${qs}` : '/api/boss/audit';
		return this.request<AuditListResponse>('GET', path);
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
