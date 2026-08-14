/**
 * Public i18n module for the client-rendered console.
 * Exports: locale state, translation, formatting, and locale contracts.
 * Deps: typed dictionaries and built-in Intl formatters.
 */

export { formatDateTime, formatRelativeTime, getLocale, i18n, initLocale, LOCALES, t } from './locale.svelte';
export type { Locale, MessageParams, MessageValue } from './types';
