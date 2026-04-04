// Integration tests for the dashboard PWA routes and HTML hooks.
// Verifies manifest, icon, service worker, and dashboard shell wiring.
// Depends on the cloudflare:test worker runtime.

import { SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';

describe('dashboard pwa routes', () => {
  it('serves the manifest and icon', async () => {
    const manifestRes = await SELF.fetch('https://test.local/manifest.json');
    expect(manifestRes.status).toBe(200);
    expect(manifestRes.headers.get('content-type')).toContain('application/json');
    expect(await manifestRes.json()).toMatchObject({
      name: 'hiboss',
      short_name: 'hiboss',
      start_url: '/dashboard',
      display: 'standalone',
      theme_color: '#161b22',
      background_color: '#0d1117',
    });

    const iconRes = await SELF.fetch('https://test.local/icon.svg');
    expect(iconRes.status).toBe(200);
    expect(iconRes.headers.get('content-type')).toContain('image/svg+xml');
    expect(await iconRes.text()).toContain('<svg');
  });

  it('serves the service worker and dashboard pwa hooks', async () => {
    const swRes = await SELF.fetch('https://test.local/sw.js');
    expect(swRes.status).toBe(200);
    expect(swRes.headers.get('cache-control')).toBe('no-cache');
    const swText = await swRes.text();
    expect(swText).toContain("const VERSION = 'hiboss-pwa-v1';");
    expect(swText).toContain('hiboss — reconnecting...');
    expect(swText).toContain("url.pathname.startsWith('/api/')");

    const dashboardRes = await SELF.fetch('https://test.local/dashboard');
    expect(dashboardRes.status).toBe(200);
    const dashboardHtml = await dashboardRes.text();
    expect(dashboardHtml).toContain('<link rel="manifest" href="/manifest.json">');
    expect(dashboardHtml).toContain("navigator.serviceWorker.register('/sw.js')");
  });
});
