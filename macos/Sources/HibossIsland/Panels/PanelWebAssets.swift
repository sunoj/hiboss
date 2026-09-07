// Self-contained display-only chart document loaded by the panel web leaf.
// Exports: PanelWebAssets.document.
// Dependencies: WKWebView bridge message shape and browser Canvas semantics.

enum PanelWebAssets {
    static let document = #"""
    <!doctype html>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      :root { color-scheme: light dark; font: -apple-system-body; -webkit-text-size-adjust: 100%; }
      body { margin: 0; background: transparent; color: CanvasText; }
      .root { box-sizing: border-box; padding: 1rem; }
      figure { box-sizing: border-box; margin: 0; display: grid; gap: .6rem; }
      figcaption { font-weight: 600; }
      .bars { display: flex; align-items: end; gap: .3rem; min-height: 0; border-bottom: 1px solid color-mix(in srgb, CanvasText 45%, transparent); }
      .bars i { display: block; width: 1rem; background: Highlight; }
      .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0; }
    </style>
    <main class="root"><p id="waiting">Waiting for a display mount.</p><figure hidden id="chart"><figcaption id="label"></figcaption><div class="bars" id="bars"></div><p class="sr-only" id="values"></p></figure></main>
    <script>
      const bridge = (message) => window.webkit?.messageHandlers?.hiboss?.postMessage(message);
      const prop = (definition, key, fallback) => definition[key] ?? fallback;
      function render(message) {
        const definition = message.definition || {};
        const values = Array.isArray(definition.values) ? definition.values.filter((value) => typeof value === 'number' && Number.isFinite(value)) : [];
        document.getElementById('waiting').hidden = true;
        document.getElementById('chart').hidden = false;
        document.getElementById('chart').style.height = `${message.state?.chartHeight || 240}px`;
        document.getElementById('label').textContent = prop(definition, 'label', 'Line chart');
        document.getElementById('values').textContent = `Values: ${values.join(', ') || 'No values'}`;
        document.getElementById('bars').replaceChildren(...values.map((value) => { const bar = document.createElement('i'); bar.style.height = `${Math.max(4, Math.min(100, value))}%`; return bar; }));
        requestAnimationFrame(() => bridge({ kind: 'contentSizeChanged', panelId: message.panelId, contentHeight: document.body.scrollHeight }));
      }
      window.__hibossBridge = { receive: (message) => message?.kind === 'mount' ? render(message) : bridge({ kind: 'renderFailed', panelId: message?.panelId || 'unknown', message: 'Malformed host message' }) };
    </script>
    """#
}
