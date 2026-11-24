<!-- Locale and appearance controls shared by Connect and Account.
     Appearance defaults to the operating system. -->
<script lang="ts">
	import { onMount } from 'svelte';
	import { i18n, LOCALES, t, type Locale } from '$lib/i18n';

	let theme = $state('system');
	const languageKeys = {
		en: 'language.en', 'zh-CN': 'language.zh', ja: 'language.ja', ko: 'language.ko'
	} as const;

	onMount(() => { theme = localStorage.getItem('hiboss.web.appearance') ?? 'system'; });

	function change(event: Event) {
		theme = (event.currentTarget as HTMLSelectElement).value;
		localStorage.setItem('hiboss.web.appearance', theme);
		if (theme === 'system') delete document.documentElement.dataset.theme;
		else document.documentElement.dataset.theme = theme;
	}
</script>

<label>
	{t('language.label')}
	<select value={i18n.locale} onchange={(event) => i18n.setLocale(event.currentTarget.value as Locale)}>
		{#each LOCALES as option (option)}<option value={option}>{t(languageKeys[option])}</option>{/each}
	</select>
</label>
<label>
	{t('console.appearance')}
	<select value={theme} onchange={change}>
		<option value="system">{t('console.systemTheme')}</option>
		<option value="light">{t('console.light')}</option>
		<option value="dark">{t('console.dark')}</option>
	</select>
</label>

<style>
	label { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 8px; }
	select { min-height: var(--hit); border: 1px solid var(--field-border); border-radius: var(--r-s); }
</style>
