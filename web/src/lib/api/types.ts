/** Boss API domain types — mirrors server MessageResponse / overview shapes. */

import type { Direction, MessageStatus, Priority, SessionStatus } from '$lib/design/semantics';

export type Mode = 'async' | 'blocking';
export type Channel = 'discord' | 'telegram' | 'email' | 'api';
export type BossRole = 'admin' | 'manager' | 'viewer';
export type AuditActorType = 'boss' | 'agent' | 'system';

export interface BossMe {
	id: string;
	token_id: string;
	name: string;
	role: string;
	agent_ids?: string[];
	preferences?: Record<string, unknown> | null;
}

export interface BossOverview {
	kpis: {
		activeSessions: number;
		workingSessions: number;
		pendingDecisions: number;
		blockingPending: number;
		unread1h: number;
	};
	priorityDistribution: Record<Priority, number>;
	sessionStatus: Record<string, number>;
	channels: ChannelHealth[];
}

export interface ChannelHealth {
	channel: string;
	configured: boolean;
}

export interface MessageMetadata {
	options?: unknown;
	options_expired?: boolean;
	[key: string]: unknown;
}

export interface MessageResponse {
	id: string;
	agent_id: string;
	direction: Direction;
	mode: Mode;
	channel: Channel | null;
	body: string;
	status: MessageStatus;
	reply_to: string | null;
	priority: Priority;
	type: string | null;
	target_agent_id?: string | null;
	target_session_id?: string | null;
	session_id?: string | null;
	idempotency_key?: string | null;
	metadata: MessageMetadata | null;
	expires_at?: string | null;
	created_at: string;
	updated_at: string;
	replies?: MessageResponse[];
	agent_name?: string | null;
	session_label?: string | null;
	session_branch?: string | null;
	session_status?: string | null;
}

export interface MessagesListResponse {
	messages: MessageResponse[];
	total: number;
}

export interface MessagesQuery {
	direction?: 'all' | 'agent_to_boss';
	limit?: number;
	offset?: number;
	priority?: Priority | string;
	session?: string;
	search?: string;
	unread?: boolean;
	agent?: string;
}

export interface SessionResponse {
	id: string;
	label: string | null;
	branch: string | null;
	cwd: string | null;
	status: SessionStatus | string;
	status_text: string | null;
	agent_name: string | null;
	agent_id?: string;
	last_seen_at: string;
	started_at?: string | null;
}

export interface SessionsListResponse {
	sessions: SessionResponse[];
}

export interface AgentResponse {
	id: string;
	name: string;
	role: string | null;
	last_used_at: string | null;
	created_at: string;
}

export interface AgentsListResponse {
	agents: AgentResponse[];
}

export interface BossRecord {
	id: string;
	name: string;
	role: BossRole;
	telegram_user_id: string | null;
	discord_user_id: string | null;
	agent_id: string | null;
	preferences: Record<string, unknown> | string | null;
	created_at: string;
	agent_ids?: string[];
}

export interface BossesListResponse {
	bosses: BossRecord[];
}

export interface BossCreateRequest {
	name: string;
	role?: BossRole;
	telegram_user_id?: string | null;
	discord_user_id?: string | null;
	agent_id?: string | null;
}

export interface BossUpdateRequest {
	name?: string;
	role?: BossRole;
	telegram_user_id?: string | null;
	discord_user_id?: string | null;
	agent_id?: string | null;
	preferences?: Record<string, unknown> | null;
}

export interface BossTokenResponse {
	id: string;
	name: string;
	token: string;
}

export interface OkResponse {
	ok: true;
}

export interface GroupResponse {
	id: string;
	name: string;
	description: string | null;
	owner_id?: string;
	created_at: string;
	member_count: number;
}

export type GroupWriteResponse = Omit<GroupResponse, 'member_count'>;

export interface GroupsListResponse {
	groups: GroupResponse[];
}

export interface RoutingRuleResponse {
	id: string;
	owner_id: string;
	channel: Channel;
	pattern: string;
	target_agent_id: string;
	priority: number;
	enabled: number;
	created_at: string;
}

export interface RoutingRulesListResponse {
	rules: RoutingRuleResponse[];
}

export interface CreateGroupRequest {
	name: string;
	description?: string;
	owner_agent_id: string;
}

export interface GroupMemberRequest {
	agent_id: string;
}

export interface BroadcastGroupRequest {
	body: string;
	priority?: Priority;
}

export interface BroadcastGroupResponse {
	messages: { agent_id: string; message_id: string }[];
	count: number;
}

export interface CreateRoutingRuleRequest {
	owner_agent_id: string;
	channel: Channel;
	pattern: string;
	target_agent_id: string;
	priority?: number;
}

export interface AgentConfigUpdateRequest {
	default_priority?: Priority;
	rate_limit?: number | null;
	channel_routing?: Record<string, Channel> | null;
}

export interface AgentConfigResponse {
	default_priority: Priority;
	rate_limit: number | null;
	channel_routing: Record<string, Channel> | null;
}

export interface BossChannelConfig {
	[key: string]: string | number | boolean | null;
	id: string;
	agent_id: string;
	agent_name: string;
	channel: Channel;
	configured: boolean;
	enabled: number;
	created_at: string;
}

export interface BossSystemResponse {
	server_time: string;
	db_ok: boolean;
	channels: ChannelHealth[];
	active_sessions: number;
	pending_decisions: number;
}

export interface AuditEntry {
	id: string;
	actor_type: AuditActorType;
	actor_id: string;
	action: string;
	resource_type: string | null;
	resource_id: string | null;
	details: string | null;
	created_at: string;
}

export interface AuditQuery {
	actor_type?: AuditActorType;
	action?: string;
	limit?: number;
	offset?: number;
}

export interface AuditListResponse {
	entries: AuditEntry[];
	total: number;
}

export interface ReplyRequest {
	body: string;
}

export interface ReactRequest {
	emoji: string;
}

export interface ForwardRequest {
	channel: 'discord' | 'telegram';
}

export type StreamEvent =
	| { type: 'message'; data: MessageResponse }
	| { type: 'resolved'; data: { id: string; status: 'replied' | 'expired' } }
	| { type: 'keepalive' };

export interface ConnectionConfig {
	baseUrl: string;
	token: string;
}

export class ApiError extends Error {
	readonly status: number;
	readonly body: string;

	constructor(status: number, body: string) {
		super(body || `HTTP ${status}`);
		this.name = 'ApiError';
		this.status = status;
		this.body = body;
	}
}
