<!-- The shared HiBoss scene follows the console's appearance.
     The illustration is decorative; the enclosing screen supplies the state. -->
<img class="day" src="/island-day.svg" alt="" width="210" height="110" />
<img class="night" src="/island-night.svg" alt="" width="210" height="110" />

<style>
	img { display: block; width: min(100%, 210px); height: auto; margin-inline: auto; }
	.night { display: none; }
	:global(:root[data-theme="dark"]) .day { display: none; }
	:global(:root[data-theme="dark"]) .night { display: block; }
	@media (prefers-color-scheme: dark) {
		:global(:root:not([data-theme="light"])) .day { display: none; }
		:global(:root:not([data-theme="light"])) .night { display: block; }
	}
</style>
