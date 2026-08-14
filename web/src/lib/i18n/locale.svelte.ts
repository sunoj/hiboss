/**
 * Client-side locale state, persistence, translation, and document language.
 * Exports: i18n, t, getLocale, initLocale, locale formatters.
 * Deps: browser storage and the typed locale dictionaries.
 */

import { enMessages, type MessageKey } from './en';
import { jaMessages } from './ja';
import { koMessages } from './ko';
import { zhMessages } from './zh';
import type { Locale, MessageParams, MessageValue } from './types';

export const LOCALES: readonly Locale[] = ['en', 'zh-CN', 'ja', 'ko'];
const STORAGE_KEY = 'hiboss.locale';
const dictionaries = { en: enMessages, 'zh-CN': zhMessages, ja: jaMessages, ko: koMessages } as const;

function localeFromLanguage(language: string): Locale {
	if (language.toLowerCase().startsWith('zh')) return 'zh-CN';
	if (language.toLowerCase().startsWith('ja')) return 'ja';
	if (language.toLowerCase().startsWith('ko')) return 'ko';
	return 'en';
}

function isLocale(value: string): value is Locale {
	return (LOCALES as readonly string[]).includes(value);
}

function storedLocale(): Locale | null {
	try {
		const value = window.localStorage.getItem(STORAGE_KEY);
		return value && isLocale(value) ? value : null;
	} catch {
		return null;
	}
}

function persistLocale(locale: Locale): void {
	try {
		window.localStorage.setItem(STORAGE_KEY, locale);
	} catch {
		// Storage can be unavailable in privacy-restricted browser contexts.
	}
}

function interpolate(value: string, params: MessageParams): string {
	return value.replace(/\{(\w+)\}/g, (_, key: string) => String(params[key] ?? `{${key}}`));
}

class I18n {
	locale = $state<Locale>('en');

	init(): void {
		if (typeof window === 'undefined') return;
		this.setLocale(storedLocale() ?? localeFromLanguage(navigator.language), false);
	}

	setLocale(next: Locale, persist = true): void {
		this.locale = next;
		if (typeof document !== 'undefined') document.documentElement.lang = next;
		if (persist && typeof window !== 'undefined') persistLocale(next);
	}

	text(key: MessageKey, params: MessageParams = {}): string {
		const value: MessageValue = dictionaries[this.locale][key] ?? enMessages[key];
		return typeof value === 'function' ? value(params) : interpolate(value, params);
	}
}

export const i18n = new I18n();

export function initLocale(): void {
	i18n.init();
}

export function getLocale(): Locale {
	return i18n.locale;
}

export function t(key: MessageKey, params: MessageParams = {}): string {
	return i18n.text(key, params);
}

export function formatRelativeTime(iso: string, nowMs = Date.now()): string {
	const then = Date.parse(iso);
	if (Number.isNaN(then)) return '—';
	const deltaSec = Math.round((nowMs - then) / 1000);
	if (Math.abs(deltaSec) < 1) return t('time.justNow');
	const abs = Math.abs(deltaSec);
	const unit = abs < 60 ? 'second' : abs < 3600 ? 'minute' : abs < 172800 ? 'hour' : 'day';
	const divisor = unit === 'second' ? 1 : unit === 'minute' ? 60 : unit === 'hour' ? 3600 : 86400;
	const value = Math.round(deltaSec / divisor);
	return new Intl.RelativeTimeFormat(getLocale(), { numeric: 'always' }).format(-value, unit);
}

export function formatDateTime(iso: string): string {
	const ms = Date.parse(iso);
	if (Number.isNaN(ms)) return '—';
	return new Intl.DateTimeFormat(getLocale(), {
		year: 'numeric',
		month: 'short',
		day: 'numeric',
		hour: '2-digit',
		minute: '2-digit',
		second: '2-digit'
	}).format(new Date(ms));
}
