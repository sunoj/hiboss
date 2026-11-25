// Preserves links to the previous console location.
// SvelteKit redirects into the reorganized console.
import { redirect } from '@sveltejs/kit';

export function load() {
	redirect(308, '/delivery?tab=rules');
}
