// Message filter construction and positional binding contracts.
// Preserves the named message-helper regression scenarios.
// Depends on Vitest and message helpers.

import { describe, expect, it } from 'vitest';
import {
  buildFilters,
} from '../message-helpers';

it('buildFilters builds agent-only filter', () => {
  const { where, binds } = buildFilters('agent-1', null, null);
  expect(where).toBe('(agent_id = ? OR target_agent_id = ?)');
  expect(binds).toEqual(['agent-1', 'agent-1']);
});

it('buildFilters adds direction filter', () => {
  const { where, binds } = buildFilters('agent-1', 'agent_to_boss', null);
  expect(where).toContain('direction = ?');
  expect(binds).toContain('agent_to_boss');
});

it('buildFilters adds status filter', () => {
  const { where, binds } = buildFilters('agent-1', null, 'sent');
  expect(where).toContain('status = ?');
  expect(binds).toContain('sent');
});

it('buildFilters adds priority IN filter', () => {
  const { where, binds } = buildFilters('agent-1', null, null, ['critical', 'high']);
  expect(where).toContain('priority IN (?, ?)');
  expect(binds).toContain('critical');
  expect(binds).toContain('high');
});

it('buildFilters combines all filters', () => {
  const { where, binds } = buildFilters('a1', 'boss_to_agent', 'read', ['normal']);
  expect(where).toContain('direction = ?');
  expect(where).toContain('status = ?');
  expect(where).toContain('priority IN (?)');
  expect(binds).toContain('boss_to_agent');
  expect(binds).toContain('read');
  expect(binds).toContain('normal');
});

it('buildFilters ignores empty priority array', () => {
  const { where } = buildFilters('a1', null, null, []);
  expect(where).not.toContain('priority');
});

it('buildFilters uses status-aware filter for unread (boss=sent, a2a=sent+delivered)', () => {
  const { where, binds } = buildFilters('a1', null, null, undefined, undefined, undefined, true);
  expect(where).toContain("direction = 'boss_to_agent' AND status = 'sent'");
  expect(where).toContain("direction = 'agent_to_agent' AND status IN ('sent', 'delivered')");
  expect(binds).toContain('a1');
});

it('buildFilters uses sent+delivered for unread a2a-only filter', () => {
  const { where } = buildFilters('a1', 'agent_to_agent', null, undefined, undefined, undefined, true);
  expect(where).toContain("direction = 'agent_to_agent'");
  expect(where).toContain("status IN ('sent', 'delivered')");
});

it('buildFilters includes target_session_id in unread filter when provided', () => {
  const { where, binds } = buildFilters(
    'a1', null, null, undefined, undefined, undefined, true, undefined, 'sess-123',
  );
  expect(where).toContain("target_session_id IS NULL OR target_session_id = ?");
  expect(where).toContain('target_session_id = ?');
  expect(binds).toContain('sess-123');
});

it('buildFilters adds from filter', () => {
  const { where, binds } = buildFilters('a1', null, null, undefined, undefined, undefined, false, 'sender');
  expect(where).toContain('agent_id IN');
  expect(binds).toContain('sender');
});

it('buildFilters adds session filter in non-unread mode', () => {
  const { where, binds } = buildFilters('a1', null, null, undefined, undefined, 'sess-abc');
  expect(where).toContain('session_id = ?');
  expect(where).toContain("direction = 'boss_to_agent'");
  expect(where).toContain('target_session_id = ?');
  expect(binds).toContain('sess-abc');
});

it('buildFilters skips session filter in unread mode', () => {
  const { where } = buildFilters('a1', null, null, undefined, undefined, 'sess-abc', true);
  // In unread mode, session filter is not applied (target_session is used instead)
  expect(where).not.toContain('session_id = ?');
});

it('buildFilters adds search filter with LIKE', () => {
  const { where, binds } = buildFilters(
    'a1', null, null, undefined, undefined, undefined, false, undefined, undefined, 'deploy',
  );
  expect(where).toContain('body LIKE ?');
  expect(binds).toContain('%deploy%');
});

it('buildFilters scopes target_session visibility to the targeted agent', () => {
  const { where, binds } = buildFilters(
    'a1', null, null, undefined, undefined, undefined, false, undefined, 'sess-123',
  );
  expect(where).toContain('(target_session_id = ? AND target_agent_id = ?)');
  expect(binds).toEqual(['a1', 'a1', 'sess-123', 'a1']);
});

it('buildFilters adds type filter', () => {
  const { where, binds } = buildFilters('a1', null, null, undefined, 'task_update');
  expect(where).toContain('type = ?');
  expect(binds).toContain('task_update');
});

it('buildFilters combines search with other filters', () => {
  const { where, binds } = buildFilters(
    'a1', 'agent_to_boss', null, ['high'], undefined, undefined, false, undefined, undefined, 'urgent',
  );
  expect(where).toContain('body LIKE ?');
  expect(where).toContain('direction = ?');
  expect(where).toContain('priority IN (?)');
  expect(binds).toContain('%urgent%');
});
