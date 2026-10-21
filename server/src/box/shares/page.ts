// Renders script-free, escaped public Box pages with a small responsive stylesheet.
// Exports the renderer for the public capability router.
import type { BoxRow } from '../types';

export function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;',
    '"': '&quot;', "'": '&#39;' })[char] ?? char);
}

function content(item: BoxRow, token: string): string {
  const file = `./${encodeURIComponent(token)}/file`;
  if (item.kind === 'text') return `<pre>${escapeHtml(item.text ?? '')}</pre>`;
  if (item.kind === 'link') {
    const label = escapeHtml(item.url ?? '');
    try {
      const url = new URL(item.url ?? '');
      if (url.protocol === 'http:' || url.protocol === 'https:') {
        return `<a href="${escapeHtml(url.href)}" rel="noopener noreferrer nofollow">${label}</a>`;
      }
    } catch { /* Invalid URLs remain plain text. */ }
    return `<p>${label}</p>`;
  }
  if (item.kind === 'image') return `<img src="${file}" alt="${escapeHtml(item.note ?? '')}">`;
  if (item.kind === 'video') return `<video controls src="${file}"></video>`;
  return `<a href="${file}">Download</a> <span>${escapeHtml(item.media_type ?? '')}
    · ${escapeHtml(String(item.media_bytes ?? 0))} bytes</span>`;
}

export function sharePage(item: BoxRow, token: string, expires: string): string {
  const title = escapeHtml(item.note ?? item.text?.split('\n')[0] ?? item.url ?? 'Box item');
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>${title}</title>
<style>:root{color-scheme:light dark}body{font:17px system-ui;max-width:48rem;margin:2rem auto;
 padding:0 1rem;overflow-wrap:anywhere}pre{white-space:pre-wrap}img,video{max-width:100%}
 @media(prefers-color-scheme:dark){body{background:#161616;color:#eee}}footer{margin-top:2rem}</style>
</head><body><h1>${title}</h1>${content(item, token)}
<footer>Expires ${escapeHtml(expires)}</footer></body></html>`;
}
