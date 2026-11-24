// Synthetic API responses used by the remote console screenshot suite.
// No external services or real credentials are involved.

const now = new Date().toISOString();
const due = new Date(Date.now() + 18 * 60000).toISOString();
const agent = {
	id: 'builder-01', name: 'Builder One', role: 'builder', project_slugs: ['atlas-api'],
	created_at: now, last_used_at: now
};
const session = {
	id: 'release-session', agent_id: agent.id, agent_name: agent.name, status: 'working',
	label: 'atlas-api', project_slug: 'atlas-api', branch: 'release/v2.4', status_text: 'Running deployment checks',
	started_at: now, last_seen_at: now, cwd: '/workspace/atlas-api'
};
const message = {
	agent_id: agent.id, agent_name: agent.name, session_id: session.id,
	session_label: session.label, session_branch: session.branch,
	direction: 'agent_to_boss', created_at: now, updated_at: now,
	priority: 'normal', status: 'delivered', mode: 'async', channel: 'api'
};
const decision = {
	...message, id: 'decision-fixture', body: 'Deploy migration 0052 to production?',
	mode: 'blocking', expires_at: due,
	metadata: {
		options: ['Deploy', 'Not yet'], default_option: 'Not yet', ask_deadline: true,
		content: '### Changes\nAdds an index needed for the release.\n\n> The staging replay passed.'
	}
};
const card = JSON.stringify({
	color: 2263842, title: 'Liquidation monitor', description: 'The monitor detected a **price change**.',
	fields: [{ name: 'Market', value: 'ETH / USDC', inline: true }, { name: 'Severity', value: 'Warning', inline: true }],
	footer: 'Market alerts', timestamp: now
});

const result = {
	...message, id: 'result-fixture', body: 'Market warning on Base',
	metadata: {
		integration: true, content: 'Fallback content',
		rich_content: '\x60\x60\x60hiboss-embed\n' + card
			+ '\n\x60\x60\x60\n\n\x60\x60\x60copy Market identifier\nbase:ETH-USDC\n\x60\x60\x60'
	}
};

const people = [
	{ id: 'boss', name: 'Robin', role: 'admin', archived_at: null, agent_ids: [] },
	{ id: 'reviewer', name: 'Morgan', role: 'manager', archived_at: null, agent_ids: [agent.id] },
	{ id: 'observer', name: 'Taylor', role: 'viewer', archived_at: null, agent_ids: [] }
];

export async function mockApi(page) {
	await page.route('**/api/**', async (route) => {
		const path = new URL(route.request().url()).pathname;
		if (path === '/api/boss/stream') {
			const body = 'event: message\ndata: ' + JSON.stringify(decision) + '\n\nevent: ready\ndata: {}\n\n';
			return route.fulfill({ contentType: 'text/event-stream', body });
		}
		const data = {
			'/api/boss/messages': { messages: [result, decision], total: 2 },
			'/api/boss/messages/decision-fixture': { ...decision, replies: [] },
			'/api/boss/messages/result-fixture': { ...result, replies: [] },
			'/api/boss/sessions': { sessions: [session] },
			'/api/boss/sessions/release-session/notes': { notes: [] },
			'/api/boss/agents': { agents: [agent] },
			'/api/boss/join-requests': { requests: [] },
			'/api/boss/channels': [],
			'/api/bosses': { bosses: people }
		}[path];
		return data ? route.fulfill({ json: data }) : route.fulfill({ status: 404, body: 'fixture route absent' });
	});
}
