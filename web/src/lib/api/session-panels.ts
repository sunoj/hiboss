// Reads scoped panel metadata for the transcript's summary rows.
// Panels stay summarized and questionnaire answers stay in the native apps.

import type { BossApiClient } from './client';

interface Panel {
	panelId: string;
	sessionId: string;
	title: string;
	createdAt: string;
	lifecycle: { taskState: string; lastObservedAt: string | null };
}

export interface PanelSummary extends Panel {
	questionnaire: boolean;
}

async function get<T>(client: BossApiClient, path: string, signal: AbortSignal): Promise<T | null> {
	const response = await fetch(client.baseUrl + path, {
		headers: { Authorization: 'Bearer ' + client.token, Accept: 'application/json' }, signal
	});
	return response.ok ? await response.json() as T : null;
}

export async function sessionPanels(client: BossApiClient, id: string, signal: AbortSignal): Promise<PanelSummary[]> {
	const rows: Panel[] = [];
	let cursor: string | null = null;
	do {
		const path: string = '/api/panels?limit=100' + (cursor ? '&cursor=' + encodeURIComponent(cursor) : '');
		const page: { panels: Panel[]; nextCursor: string | null } | null = await get(client, path, signal);
		if (!page) break;
		rows.push(...page.panels.filter((panel) => panel.sessionId === id));
		cursor = page.nextCursor;
	} while (cursor && !signal.aborted);
	return Promise.all(rows.map(async (panel) => {
		const path = '/api/panels/' + encodeURIComponent(panel.panelId) + '/requests';
		const requests = await get<{ requests: { state: string }[] }>(client, path, signal).catch(() => null);
		return { ...panel, questionnaire: requests?.requests.some(({ state }) => state === 'open') ?? false };
	}));
}
