# HiBoss web console

A SvelteKit single-page app for bosses: agents and their keys, bosses and grants,
messages, sessions, projects, notification destinations, devices, routing and audit.
It is a static build (`@sveltejs/adapter-static` with an `index.html` fallback) and
talks to the HiBoss server directly from the browser.

## Develop

```sh
cd web
npm ci
npm run dev          # http://localhost:5173
```

A server with `CONSOLE_ORIGIN` unset accepts requests from localhost origins, so a local
console can use a deployed or a local (`npm run dev` in `server/`) server.

## Test

```sh
npm test             # Vitest unit tests
npm run check        # svelte-check type checking
```

## Build and deploy

```sh
npm run build        # static output in web/build/
```

Serve `web/build/` from any static host that falls back to `index.html` for unknown
paths. With Cloudflare Pages:

```sh
npx wrangler pages project create hiboss-console
npx wrangler pages deploy build --project-name hiboss-console
```

Then allow the console's origin on the server: set `CONSOLE_ORIGIN` in
`server/wrangler.toml` to the Pages URL (for example `https://hiboss-console.pages.dev`;
its preview subdomains are allowed too) and redeploy the server.

## Sign in

The console signs in with a server URL and a boss token (`hb_boss_…`). The token is kept
in the browser's `localStorage` until you disconnect.

To get a token for the console, create a pairing code from a paired iPhone or Mac app,
then redeem it once:

```sh
curl -sS -X POST "https://<server>/api/pairing/redeem" \
  -H 'content-type: application/json' \
  -d '{"code":"<pairing-code>","device_label":"Web console"}'
```

The response's `token` is a new boss token for the same boss, listed as its own client
and revocable from the apps or the console's Devices page. What the console shows and
allows follows that boss's role and agent grants.
