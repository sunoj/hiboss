// Covers explicit agent capabilities and legacy message metadata.
// Includes independent checks for viewer, manager, and admin access.
import { describe, expect, it } from 'vitest';
import { canSetAgentAdmin, isIntegrationMessage } from './agent-capabilities';
import type { AgentResponse } from './types';

const legacy: AgentResponse = {
	id: 'fixture', name: 'Builder', role: 'builder', last_used_at: null, created_at: '2026-09-12T00:00:00Z'
};

describe('agent capability fields', () => {
	it('uses legacy integration metadata when kind is absent', () => {
		expect(isIntegrationMessage({ agent_id: legacy.id, metadata: { source: 'webhook' } }, [legacy])).toBe(true);
		expect(isIntegrationMessage({ agent_id: legacy.id, metadata: null }, [legacy])).toBe(false);
		expect(canSetAgentAdmin(legacy, 'admin')).toBe(false);
	});

	it('uses explicit kind and only exposes the switch to admins when supported', () => {
		expect(isIntegrationMessage({ agent_id: legacy.id, metadata: null }, [{ ...legacy, kind: 'integration' }]))
			.toBe(true);
		expect(isIntegrationMessage({ agent_id: legacy.id, metadata: { integration: true } },
			[{ ...legacy, kind: 'agent' }])).toBe(false);
		const agent = { ...legacy, admin: false };
		expect(canSetAgentAdmin(agent, 'admin')).toBe(true);
		expect(canSetAgentAdmin(agent, 'manager')).toBe(false);
		expect(canSetAgentAdmin(agent, 'viewer')).toBe(false);
	});
});
