/**
 * Navigation definitions for the web console shell.
 * Exports: NavModule, NAV_MODULES, isActivePath.
 * Deps: typed i18n message keys.
 */

import type { MessageKey } from '$lib/i18n/en';

export interface NavModule {
	id: string;
	href: string;
	labelKey: MessageKey;
	shortKey: MessageKey;
	primary: boolean;
}

export const NAV_MODULES: readonly NavModule[] = [
	{ id: 'today', href: '/', labelKey: 'nav.dashboard', shortKey: 'nav.short.dashboard', primary: true },
	{ id: 'sessions', href: '/sessions', labelKey: 'nav.sessions', shortKey: 'nav.short.sessions', primary: true },
	{ id: 'messages', href: '/messages', labelKey: 'nav.messages', shortKey: 'nav.short.messages', primary: true },
	{ id: 'agents', href: '/agents', labelKey: 'nav.agents', shortKey: 'nav.short.agents', primary: false },
	{ id: 'delivery', href: '/delivery', labelKey: 'console.delivery', shortKey: 'console.delivery', primary: false },
	{ id: 'projects', href: '/projects', labelKey: 'nav.projects', shortKey: 'nav.short.projects', primary: false },
	{ id: 'access', href: '/access', labelKey: 'nav.bosses', shortKey: 'nav.short.bosses', primary: false },
	{ id: 'audit', href: '/audit', labelKey: 'nav.audit', shortKey: 'nav.short.audit', primary: false },
	{ id: 'server', href: '/server', labelKey: 'nav.system', shortKey: 'nav.short.system', primary: false }
];

export function isActivePath(pathname: string, href: string): boolean {
	if (href === '/') return pathname === '/' || pathname === '';
	return pathname === href || pathname.startsWith(`${href}/`);
}
