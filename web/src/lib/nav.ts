/** Module nav definitions for the web console shell. */

export interface NavModule {
	id: string;
	href: string;
	label: string;
	short: string;
	primary: boolean;
}

export const NAV_MODULES: readonly NavModule[] = [
	{ id: 'dashboard', href: '/', label: 'Dashboard', short: '总览', primary: true },
	{ id: 'messages', href: '/messages', label: 'Messages', short: '消息', primary: true },
	{ id: 'sessions', href: '/sessions', label: 'Sessions', short: '会话', primary: true },
	{ id: 'agents', href: '/agents', label: 'Agents', short: '智能体', primary: false },
	{ id: 'groups', href: '/groups', label: 'Groups', short: '分组', primary: false },
	{ id: 'bosses', href: '/bosses', label: 'Bosses & Access', short: '权限', primary: false },
	{ id: 'routing', href: '/routing', label: 'Routing', short: '路由', primary: false },
	{ id: 'channels', href: '/channels', label: 'Channels', short: '渠道', primary: false },
	{ id: 'audit', href: '/audit', label: 'Audit', short: '审计', primary: false },
	{ id: 'system', href: '/system', label: 'System / Doctor', short: '系统', primary: false }
] as const;

export function isActivePath(pathname: string, href: string): boolean {
	if (href === '/') return pathname === '/' || pathname === '';
	return pathname === href || pathname.startsWith(`${href}/`);
}
