<script lang="ts">
	import type { AuditActorType } from '$lib/api/types';
	import {
		ACTOR_TYPES,
		COMMON_ACTIONS,
		PAGE_SIZE_OPTIONS,
		actorTypeLabel,
		type ActorTypeFilter,
		type AuditFilterState
	} from './audit-helpers';
	import { t } from '$lib/i18n';

	interface Props {
		filters: AuditFilterState;
		onChange: (next: AuditFilterState) => void;
		onSubmit: () => void;
	}

	let { filters, onChange, onSubmit }: Props = $props();

	function setActorType(actor_type: ActorTypeFilter) {
		onChange({ ...filters, actor_type, offset: 0 });
	}

	function setAction(action: string) {
		onChange({ ...filters, action, offset: 0 });
	}

	function setSearch(search: string) {
		onChange({ ...filters, search });
	}

	function setLimit(limit: number) {
		onChange({ ...filters, limit, offset: 0 });
	}

	function handleSubmit(e: Event) {
		e.preventDefault();
		onSubmit();
	}
</script>

<form class="filters" onsubmit={handleSubmit}>
	<div class="row">
		<label class="field">
			<span class="label">{t('form.actorType')}</span>
			<select
				value={filters.actor_type}
				onchange={(e) => setActorType(e.currentTarget.value as ActorTypeFilter)}
			>
				<option value="all">{t('common.nothing')}</option>
				{#each ACTOR_TYPES as t (t)}
					<option value={t}>{actorTypeLabel(t as AuditActorType)}</option>
				{/each}
			</select>
		</label>

		<label class="field grow">
			<span class="label">{t('form.action')}</span>
			<input
				type="text"
				list="audit-actions"
				placeholder={t('form.actionExample')}
				value={filters.action}
				oninput={(e) => setAction(e.currentTarget.value)}
			/>
			<datalist id="audit-actions">
				{#each COMMON_ACTIONS as action (action)}
					<option value={action}></option>
				{/each}
			</datalist>
		</label>

		<label class="field">
			<span class="label">{t('form.pageSize')}</span>
			<select
				value={String(filters.limit)}
				onchange={(e) => setLimit(Number(e.currentTarget.value))}
			>
				{#each PAGE_SIZE_OPTIONS as size (size)}
					<option value={String(size)}>{size}</option>
				{/each}
			</select>
		</label>

		<label class="field grow wide">
			<span class="label">{t('form.searchPage')}</span>
			<input
				type="search"
				placeholder={t('form.searchAudit')}
				value={filters.search}
				oninput={(e) => setSearch(e.currentTarget.value)}
			/>
		</label>

		<button type="submit" class="apply">{t('common.apply')}</button>
	</div>
</form>

<style>
	@import '../../lib/design/filter-panel.css';
	.apply {
		border: 1px solid var(--hb-accent);
		background: color-mix(in srgb, var(--hb-accent) 22%, var(--hb-bg-elevated));
		color: var(--hb-text);
		padding: 0.35rem 0.75rem;
		align-self: flex-end;
	}
	.apply:hover {
		background: color-mix(in srgb, var(--hb-accent) 35%, var(--hb-bg-elevated));
	}
</style>
