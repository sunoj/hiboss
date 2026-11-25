// Interprets optional agent fields while preserving older server behavior.
// Message metadata remains available when the agent kind is absent.

import type { AgentResponse, MessageResponse } from './types';

export function isIntegrationMessage(
	message: Pick<MessageResponse, 'agent_id' | 'metadata'>, agents: AgentResponse[]
): boolean {
	const kind = agents.find(({ id }) => id === message.agent_id)?.kind;
	if (kind !== undefined) return kind === 'integration';
	const metadata = message.metadata;
	return metadata?.integration === true || metadata?.source === 'webhook'
		|| metadata?.rich_content !== undefined;
}

export function canSetAgentAdmin(agent: AgentResponse, role: string | undefined): boolean {
	return role === 'admin' && typeof agent.admin === 'boolean';
}
