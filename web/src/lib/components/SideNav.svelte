<script lang="ts">
	import { page } from '$app/stores';
	import { t, i18n } from '$lib/i18n';
	import { NAV_MODULES, isActivePath } from '$lib/nav';
</script>

<aside class="nav" aria-label={t('nav.aria')}>
	<div class="brand">
		<span class="mark">hb</span>
		<div>
			<div class="name">hiboss</div>
			<div class="sub">{t('brand.console')}</div>
		</div>
	</div>
	<nav>
		{#each NAV_MODULES as mod (mod.id)}
			<a
				href={mod.href}
				class:active={isActivePath($page.url.pathname, mod.href)}
				class:primary={mod.primary}
			>
				<span class="label">{t(mod.labelKey)}</span>
				<span class="short">{t(mod.shortKey)}</span>
			</a>
		{/each}
	</nav>
</aside>

<style>
	.nav {
		width: var(--hb-nav-width);
		flex-shrink: 0;
		background: var(--hb-bg-elevated);
		border-right: 1px solid var(--hb-border);
		display: flex;
		flex-direction: column;
		min-height: 100vh;
		position: sticky;
		top: 0;
		align-self: flex-start;
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 0.65rem;
		padding: 0.9rem 1rem;
		border-bottom: 1px solid var(--hb-border-subtle);
		height: var(--hb-topbar-height);
		box-sizing: border-box;
	}
	.mark {
		width: 28px;
		height: 28px;
		border-radius: var(--hb-radius);
		background: var(--hb-accent);
		color: #0c0e12;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		font-weight: 800;
		font-family: var(--hb-font-mono);
		font-size: 11px;
	}
	.name {
		font-weight: 700;
		letter-spacing: -0.01em;
	}
	.sub {
		font-size: 10px;
		color: var(--hb-text-dim);
		letter-spacing: 0.06em;
	}
	nav {
		display: flex;
		flex-direction: column;
		padding: 0.5rem;
		gap: 0.15rem;
		overflow-y: auto;
	}
	a {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		gap: 0.5rem;
		padding: 0.45rem 0.55rem;
		border-radius: var(--hb-radius-sm);
		color: var(--hb-text-muted);
	}
	a.primary {
		color: var(--hb-text);
	}
	a:hover {
		background: var(--hb-bg-hover);
		color: var(--hb-text);
	}
	a.active {
		background: color-mix(in srgb, var(--hb-accent) 16%, transparent);
		color: var(--hb-text);
		box-shadow: inset 2px 0 0 var(--hb-accent);
	}
	.label {
		font-weight: 550;
	}
	.short {
		font-size: 10px;
		color: var(--hb-text-dim);
	}
</style>
