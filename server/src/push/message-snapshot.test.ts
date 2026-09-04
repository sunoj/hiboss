// Verifies APNs message snapshots used to prewarm the iOS detail cache.
// Exports: Vitest coverage for complete, malformed, and oversized snapshots.
// Dependencies: message-snapshot builder plus shared APNs/message contracts.

import { describe, expect, it } from 'vitest';
import type { ApnsPayload } from '../apns';
import type { MessageRow } from '../types';
import { attachMessageSnapshot } from './message-snapshot';

const payload: ApnsPayload = {
  aps: {
    alert: { title: 'Project', body: 'Ship it?' },
    'interruption-level': 'active',
    'thread-id': 'boss-1',
  },
  messageId: 'message-1',
};

const message: MessageRow = {
  id: 'message-1',
  agent_id: 'agent-1',
  agent_name: 'Release Agent',
  direction: 'agent_to_boss',
  mode: 'async',
  channel: 'api',
  body: 'Ship it?',
  status: 'sent',
  reply_to: null,
  priority: 'high',
  type: 'approval_request',
  target_agent_id: null,
  target_session_id: null,
  session_id: 'session-1',
  idempotency_key: null,
  metadata: JSON.stringify({ options: ['Approve', 'Wait'] }),
  expires_at: '2026-09-04T02:00:00Z',
  created_at: '2026-09-04T01:00:00Z',
  updated_at: '2026-09-04T01:00:00Z',
};

describe('attachMessageSnapshot', () => {
  it('embeds a complete decodable message while the payload fits APNs', () => {
    const result = attachMessageSnapshot(payload, message, {
      agentName: 'Release Agent',
      sessionLabel: 'hiboss/release',
      sessionBranch: 'main',
    });

    expect(result.message).toMatchObject({
      id: 'message-1',
      agent_name: 'Release Agent',
      body: 'Ship it?',
      metadata: { options: ['Approve', 'Wait'] },
      session_label: 'hiboss/release',
      session_branch: 'main',
    });
  });

  it('omits the snapshot when the APNs payload would exceed its byte limit', () => {
    const result = attachMessageSnapshot(payload, { ...message, body: '🚀'.repeat(3_000) }, {
      agentName: 'Release Agent',
      sessionLabel: null,
      sessionBranch: null,
    });

    expect(result.message).toBeUndefined();
  });

  it('omits malformed metadata instead of forwarding invalid JSON', () => {
    const result = attachMessageSnapshot(payload, { ...message, metadata: '{broken' }, {
      agentName: 'Release Agent',
      sessionLabel: null,
      sessionBranch: null,
    });

    expect(result.message).not.toHaveProperty('metadata');
  });
});
