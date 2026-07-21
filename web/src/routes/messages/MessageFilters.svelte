<script lang="ts">
	import {
		DIRECTIONS,
		MESSAGE_STATUSES,
		PRIORITIES,
		directionLabel,
		type Direction,
		type MessageStatus,
		type Priority
	} from '$lib/design/semantics';
	import {
		togglePriority,
		type DirectionFilter,
		type MessageFilterState,
		type StatusFilter,
		type ViewMode
	} from './message-helpers';

	interface Props {
		filters: MessageFilterState;
		viewMode: ViewMode;
		onChange: (next: MessageFilterState) => void;
		onViewMode: (mode: ViewMode) => void;
		onSubmit: () => void;
	}

	let { filters, viewMode, onChange, onViewMode, onSubmit }: Props = $props();

	function setDirection(direction: DirectionFilter) {
		onChange({ ...filters, direction });
	}

	function setStatus(status: StatusFilter) {
		onChange({ ...filters, status });
	}

	function setAgent(agent: string) {
		onChange({ ...filters, agent });
	}

	function setSearch(search: string) {
		onChange({ ...filters, search });
	}

	function setSession(session: string) {
		onChange({ ...filters, session });
	}

	function flipPriority(priority: Priority) {
		onChange({ ...filters, priorities: togglePriority(filters.priorities, priority) });
	}

	function handleSubmit(e: Event) {
		e.preventDefault();
		onSubmit();
	}
</script>

<form class="filters" onsubmit={handleSubmit}>
	<div class="row">
		<label class="field">
			<span class="label">Direction</span>
			<select
				value={filters.direction}
				onchange={(e) => setDirection(e.currentTarget.value as DirectionFilter)}
			>
				<option value="all">All</option>
				{#each DIRECTIONS as dir (dir)}
					<option value={dir}>{directionLabel(dir as Direction)}</option>
				{/each}
			</select>
		</label>

		<label class="field">
			<span class="label">Status</span>
			<select
				value={filters.status}
				onchange={(e) => setStatus(e.currentTarget.value as StatusFilter)}
			>
				<option value="all">All</option>
				{#each MESSAGE_STATUSES as st (st)}
					<option value={st}>{st as MessageStatus}</option>
				{/each}
			</select>
		</label>

		<label class="field grow">
			<span class="label">Agent</span>
			<input
				type="text"
				placeholder="Agent id or prefix"
				value={filters.agent}
				oninput={(e) => setAgent(e.currentTarget.value)}
			/>
		</label>

		<label class="field grow">
			<span class="label">Session</span>
			<input
				type="text"
				placeholder="Session id"
				value={filters.session}
				oninput={(e) => setSession(e.currentTarget.value)}
			/>
		</label>

		<label class="field grow wide">
			<span class="label">Search</span>
			<input
				type="search"
				placeholder="Full-text in body"
				value={filters.search}
				oninput={(e) => setSearch(e.currentTarget.value)}
			/>
		</label>
	</div>

	<div class="row priorities">
		<span class="label">Priority</span>
		<div class="chips" role="group" aria-label="Priority filters">
			{#each PRIORITIES as p (p)}
				<button
					type="button"
					class="chip"
					class:active={filters.priorities.includes(p)}
					onclick={() => flipPriority(p)}
				>
					{p}
				</button>
			{/each}
		</div>
		<div class="spacer"></div>
		<div class="view" role="group" aria-label="List view">
			<button
				type="button"
				class="chip"
				class:active={viewMode === 'flat'}
				onclick={() => onViewMode('flat')}
			>
				Flat
			</button>
			<button
				type="button"
				class="chip"
				class:active={viewMode === 'grouped'}
				onclick={() => onViewMode('grouped')}
			>
				By session
			</button>
		</div>
		<button type="submit" class="apply">Apply</button>
	</div>
</form>

<style>
	.filters {
		display: flex;
		flex-direction: column;
		gap: 0.65rem;
		padding: 0.85rem 1rem;
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		margin-bottom: 0.75rem;
	}
	.row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.55rem;
		align-items: flex-end;
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		min-width: 8rem;
	}
	.field.grow {
		flex: 1;
		min-width: 10rem;
	}
	.field.wide {
		min-width: 14rem;
	}
	.label {
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-muted);
	}
	select,
	input {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-input);
		color: var(--hb-text);
		border-radius: var(--hb-radius-sm);
		padding: 0.35rem 0.5rem;
		font: inherit;
		font-size: 12px;
	}
	.priorities {
		align-items: center;
	}
	.chips,
	.view {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
	}
	.chip {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		color: var(--hb-text-muted);
		border-radius: var(--hb-radius-sm);
		padding: 0.2rem 0.5rem;
		font-size: 11px;
		font-weight: 600;
		text-transform: uppercase;
		cursor: pointer;
	}
	.chip.active {
		border-color: var(--hb-accent);
		color: var(--hb-text);
		background: color-mix(in srgb, var(--hb-accent) 18%, var(--hb-bg-elevated));
	}
	.spacer {
		flex: 1;
	}
	.apply {
		border: 1px solid var(--hb-accent);
		background: color-mix(in srgb, var(--hb-accent) 22%, var(--hb-bg-elevated));
		color: var(--hb-text);
		border-radius: var(--hb-radius-sm);
		padding: 0.3rem 0.75rem;
		font-weight: 600;
		cursor: pointer;
	}
	.apply:hover {
		background: color-mix(in srgb, var(--hb-accent) 35%, var(--hb-bg-elevated));
	}
</style>
