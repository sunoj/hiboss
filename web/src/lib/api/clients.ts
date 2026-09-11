// Browser-client identity contracts and readable user-agent labels.
// Exports BossClient, ClientGrant, and browserLabel; used by the API and auth store.
export type ClientId = string & { readonly __brand: 'ClientId' };
export type ClientKind = 'ios' | 'macos' | 'web' | 'cli';
export interface BossClient {
	id: ClientId;
	kind: ClientKind;
	label: string;
	created_at: string;
	last_seen_at: string | null;
	revoked_at: string | null;
	has_push_device: boolean;
	has_signing_key: boolean;
	is_current: boolean;
}
export interface ClientGrant { client: BossClient; token: string }

export function browserLabel(userAgent: string): string {
	const browser = /Edg\//.test(userAgent) ? 'Edge' : /Firefox\//.test(userAgent) ? 'Firefox'
		: /Chrome\//.test(userAgent) ? 'Chrome' : /Safari\//.test(userAgent) ? 'Safari' : 'Browser';
	const platform = /iPhone|iPad/.test(userAgent) ? 'iOS' : /Android/.test(userAgent) ? 'Android'
		: /Macintosh/.test(userAgent) ? 'macOS' : /Windows/.test(userAgent) ? 'Windows' : /Linux/.test(userAgent) ? 'Linux' : '';
	return platform ? `${browser} (${platform})` : browser;
}
