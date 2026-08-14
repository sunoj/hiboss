/**
 * Shared contracts for the typed console dictionaries.
 * Exports: Locale, MessageParams, MessageValue, LocaleDictionary.
 * Deps: none.
 */

export type Locale = 'en' | 'zh-CN' | 'ja' | 'ko';

export type MessageParams = Readonly<Record<string, string | number>>;

export type MessageValue = string | ((params: MessageParams) => string);

export type LocaleDictionary<Keys extends string> = {
	readonly [K in Keys]: MessageValue;
};
