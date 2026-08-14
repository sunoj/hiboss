/**
 * Locale-aware plural selection for complete translated messages.
 * Exports: plural, PluralForms.
 * Deps: Intl.PluralRules.
 */

import type { Locale } from './types';

export type PluralForms = Partial<Record<Intl.LDMLPluralRule, string>> & {
	other: string;
};

export function plural(count: number, locale: Locale, forms: PluralForms): string {
	const category = new Intl.PluralRules(locale).select(count);
	return forms[category] ?? forms.other;
}
