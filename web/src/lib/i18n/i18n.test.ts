/**
 * Integration checks for locale switching, typed translation, and Intl output.
 * Exports: test coverage only.
 * Deps: Vitest jsdom environment and the console i18n module.
 */

import { afterEach, describe, expect, it } from 'vitest';
import { formatRelativeTime, i18n, t } from './index';

afterEach(() => {
	i18n.setLocale('en', false);
});

describe('console locale state', () => {
	it('applies an explicit locale and updates html lang', () => {
		i18n.setLocale('zh-CN', false);

		expect(i18n.locale).toBe('zh-CN');
		expect(document.documentElement.lang).toBe('zh-CN');
		expect(t('common.refresh')).toBe('刷新');
	});

	it('uses locale-aware plural messages and relative time', () => {
		i18n.setLocale('en', false);
		expect(t('common.members', { count: 1 })).toBe('1 member');
		expect(t('common.members', { count: 2 })).toBe('2 members');
		expect(formatRelativeTime('2026-07-21T11:30:00Z', Date.parse('2026-07-21T12:00:00Z'))).toBe(
			'30 minutes ago'
		);

		i18n.setLocale('ja', false);
		expect(t('common.members', { count: 2 })).toBe('2 メンバー');
	});
});
