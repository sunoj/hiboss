// Serves the dashboard PWA service worker as a plain string module.
// Exports cache/versioned source for the /sw.js route.
// Deps: browser Service Worker APIs only.

const swJs = String.raw`const VERSION = 'hiboss-pwa-v1';
const STATIC_CACHE = 'hiboss-static-' + VERSION;
const API_CACHE = 'hiboss-api-' + VERSION;
const CDN_HOSTS = ['cdn.tailwindcss.com', 'unpkg.com', 'fonts.googleapis.com', 'fonts.gstatic.com'];

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((key) => key !== STATIC_CACHE && key !== API_CACHE).map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  if (url.origin === self.location.origin && url.pathname.startsWith('/api/')) {
    event.respondWith(networkFirst(request));
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(navigate(request));
    return;
  }

  if (CDN_HOSTS.includes(url.hostname)) {
    event.respondWith(cacheFirst(request));
  }
});

async function cacheFirst(request) {
  const cache = await caches.open(STATIC_CACHE);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response.ok || response.type === 'opaque') {
    await cache.put(request, response.clone());
  }
  return response;
}

async function networkFirst(request) {
  const cache = await caches.open(API_CACHE);
  try {
    const response = await fetch(request);
    if (response.ok) {
      await cache.put(request, response.clone());
    }
    return response;
  } catch {
    const cached = await cache.match(request);
    return cached || new Response(JSON.stringify({ error: 'offline' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
    });
  }
}

async function navigate(request) {
  try {
    return await fetch(request);
  } catch {
    return offlineResponse();
  }
}

function offlineResponse() {
  return new Response(
    '<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>hiboss offline</title><style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0d1117;color:#e6edf3;font:600 16px/1.5 Inter,system-ui,sans-serif}div{padding:24px 28px;border:1px solid #30363d;border-radius:20px;background:#161b22;box-shadow:0 16px 40px rgba(0,0,0,.28)}</style></head><body><div>hiboss — reconnecting...</div></body></html>',
    { headers: { 'Content-Type': 'text/html; charset=utf-8' } },
  );
}
`;

export default swJs;
