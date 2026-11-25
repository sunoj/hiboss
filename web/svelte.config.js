import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	preprocess: vitePreprocess(),
	kit: {
		// Self-hosted SPA: static build with a client-side fallback.
		adapter: adapter({ fallback: 'index.html', strict: false }),
		// The console shares an origin with the API and keeps the boss token in localStorage, so no
		// script runs except the bundle and SvelteKit's hashed bootstrap. "Connect to a different
		// server" needs https: in connect-src; agent avatars may be remote https: images.
		csp: {
			mode: 'hash',
			directives: {
				'default-src': ['self'],
				'script-src': ['self'],
				'style-src': ['self', 'unsafe-inline'],
				'img-src': ['self', 'data:', 'blob:', 'https:'],
				'media-src': ['self', 'blob:', 'https:'],
				'connect-src': ['self', 'https:'],
				'font-src': ['self'],
				'object-src': ['none'],
				'base-uri': ['self'],
				'form-action': ['self']
			}
		}
	}
};

export default config;
