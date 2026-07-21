/** Pure mappers / formatters for boss API payloads. */

import { coercePriority, isDirection, isMessageStatus } from '$lib/design/semantics';
import type { Direction, MessageStatus, Priority } from '$lib/design/semantics';
import type { MessageMetadata, MessageResponse } from './types';

/** Extract structured options array — never split on commas. */
export function extractOptions(metadata: MessageMetadata | null | undefined): string[] {
	if (!metadata || metadata.options == null) return [];
	const raw = metadata.options;
	if (!Array.isArray(raw)) return [];
	return raw
		.map((item) => {
			if (typeof item === 'string') return item.trim();
			if (item && typeof item === 'object' && 'label' in item) {
				const label = (item as { label: unknown }).label;
				return typeof label === 'string' ? label.trim() : '';
			}
			return '';
		})
		.filter((s) => s.length > 0);
}

export function truncateBody(body: string, max = 120): string {
	const text = body.replace(/\s+/g, ' ').trim();
	if (text.length <= max) return text;
	return `${text.slice(0, max - 1)}…`;
}

export function formatRelativeTime(iso: string, nowMs = Date.now()): string {
	const then = Date.parse(iso);
	if (Number.isNaN(then)) return '—';
	const deltaSec = Math.round((nowMs - then) / 1000);
	if (deltaSec < 60) return `${Math.max(deltaSec, 0)}s ago`;
	const mins = Math.round(deltaSec / 60);
	if (mins < 60) return `${mins}m ago`;
	const hours = Math.round(mins / 60);
	if (hours < 48) return `${hours}h ago`;
	const days = Math.round(hours / 24);
	return `${days}d ago`;
}

export function priorityBarWidths(
	dist: Record<Priority, number>
): Array<{ priority: Priority; count: number; pct: number }> {
	const order: Priority[] = ['critical', 'high', 'normal', 'low'];
	const total = order.reduce((sum, p) => sum + (dist[p] ?? 0), 0);
	return order.map((priority) => {
		const count = dist[priority] ?? 0;
		const pct = total === 0 ? 0 : Math.round((count / total) * 100);
		return { priority, count, pct };
	});
}

export function sessionStatusEntries(
	counts: Record<string, number>
): Array<{ status: string; count: number }> {
	const order = ['working', 'waiting', 'blocked', 'completed', 'idle'];
	const seen = new Set<string>();
	const rows: Array<{ status: string; count: number }> = [];
	for (const status of order) {
		seen.add(status);
		rows.push({ status, count: counts[status] ?? 0 });
	}
	for (const [status, count] of Object.entries(counts)) {
		if (!seen.has(status)) rows.push({ status, count });
	}
	return rows;
}

export function normalizeMessage(raw: Record<string, unknown>): MessageResponse {
	const direction = typeof raw.direction === 'string' && isDirection(raw.direction)
		? raw.direction
		: 'agent_to_boss';
	const status = typeof raw.status === 'string' && isMessageStatus(raw.status)
		? raw.status
		: 'sent';
	const priority = coercePriority(typeof raw.priority === 'string' ? raw.priority : undefined);
	const metadata = normalizeMetadata(raw.metadata);

	return {
		id: String(raw.id ?? ''),
		agent_id: String(raw.agent_id ?? ''),
		direction: direction as Direction,
		mode: raw.mode === 'blocking' ? 'blocking' : 'async',
		channel: (raw.channel as MessageResponse['channel']) ?? null,
		body: String(raw.body ?? ''),
		status: status as MessageStatus,
		reply_to: raw.reply_to == null ? null : String(raw.reply_to),
		priority,
		type: raw.type == null ? null : String(raw.type),
		target_agent_id: raw.target_agent_id == null ? null : String(raw.target_agent_id),
		target_session_id: raw.target_session_id == null ? null : String(raw.target_session_id),
		session_id: raw.session_id == null ? null : String(raw.session_id),
		idempotency_key: raw.idempotency_key == null ? null : String(raw.idempotency_key),
		metadata,
		expires_at: raw.expires_at == null ? null : String(raw.expires_at),
		created_at: String(raw.created_at ?? ''),
		updated_at: String(raw.updated_at ?? raw.created_at ?? ''),
		agent_name: raw.agent_name == null ? null : String(raw.agent_name),
		session_label: raw.session_label == null ? null : String(raw.session_label),
		session_branch: raw.session_branch == null ? null : String(raw.session_branch),
		session_status: raw.session_status == null ? null : String(raw.session_status)
	};
}

function normalizeMetadata(value: unknown): MessageMetadata | null {
	if (value == null) return null;
	if (typeof value === 'string') {
		try {
			const parsed: unknown = JSON.parse(value);
			return typeof parsed === 'object' && parsed !== null
				? (parsed as MessageMetadata)
				: null;
		} catch {
			return null;
		}
	}
	if (typeof value === 'object') return value as MessageMetadata;
	return null;
}
