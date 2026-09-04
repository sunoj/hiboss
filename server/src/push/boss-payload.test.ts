// Verifies boss APNs payload preparation, including its privacy boundary.
// Exports: Vitest coverage for normal snapshots, private pushes, and suppression.
// Dependencies: boss-payload preparation plus persisted message contracts.

import { describe, expect, it } from 'vitest';
import type { MessageRow } from '../types';
import { prepareBossPush } from './boss-payload';

const message: MessageRow = {
  id: 'message-1',
  agent_id: 'agent-1',
  direction: 'agent_to_boss',
  mode: 'async',
  channel: 'api',
  body: 'Production credentials rotated',
  status: 'sent',
  reply_to: null,
  priority: 'high',
  type: 'text',
  target_agent_id: null,
  target_session_id: null,
  session_id: 'session-1',
  idempotency_key: null,
  metadata: JSON.stringify({ content: 'Release', options: ['Acknowledge'] }),
  created_at: '2026-09-04T01:00:00Z',
  updated_at: '2026-09-04T01:00:00Z',
};

describe('prepareBossPush', () => {
  it('prewarms normal notifications with the complete message snapshot', () => {
    const prepared = prepareBossPush(
      message,
      'Operations Agent',
      { label: 'hiboss/release', branch: 'main' },
      'boss-1',
      null,
    );

    expect(prepared?.payload.message).toMatchObject({
      id: 'message-1',
      body: 'Production credentials rotated',
      session_label: 'hiboss/release',
    });
    expect(prepared?.payload.options).toEqual(['Acknowledge']);
  });

  it('never includes a message snapshot when private push is enabled', () => {
    const prepared = prepareBossPush(
      message,
      'Operations Agent',
      { label: 'hiboss/release', branch: 'main' },
      'boss-1',
      JSON.stringify({ private_push: true }),
    );

    expect(prepared?.payload.message).toBeUndefined();
    expect(prepared?.payload.options).toBeUndefined();
    expect(prepared?.payload.aps.alert.title).toBe('HiBoss');
    expect(prepared?.payload.aps.alert.body).not.toContain(message.body);
  });

  it('returns no payload when the priority preference suppresses delivery', () => {
    const prepared = prepareBossPush(
      { ...message, priority: 'normal', metadata: null },
      'Operations Agent',
      null,
      'boss-1',
      JSON.stringify({ push: { normal: { deliver: false } } }),
    );

    expect(prepared).toBeNull();
  });
});
