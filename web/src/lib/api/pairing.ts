// Browser pairing requests and pasted pair-link normalization.
// Uses the public redemption endpoint and existing API errors.

import { normalizeBaseUrl } from './auth';
import { browserLabel } from './clients';
import { ApiError, type BossMe } from './types';

export function pairingCode(input: string): string {
	const value = input.trim();
	if (!value.startsWith('hiboss://')) return value;
	const link = new URL(value);
	return link.hostname === 'pair' ? link.searchParams.get('code') ?? '' : '';
}

export async function redeemPairing(baseUrl: string, code: string) {
	const response = await fetch(normalizeBaseUrl(baseUrl) + '/api/pairing/redeem', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({ code, device_label: 'Web console · ' + browserLabel(navigator.userAgent) })
	});
	if (!response.ok) throw new ApiError(response.status, await response.text());
	return await response.json() as { token: string; boss: Pick<BossMe, 'id' | 'name' | 'role'> };
}
