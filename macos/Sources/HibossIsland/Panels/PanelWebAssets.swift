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
      .plot { display: block; width: 100%; aspect-ratio: 8 / 1; height: auto; overflow: visible; }
      .plot .series { fill: none; stroke: Highlight; stroke-linecap: round; stroke-linejoin: round; stroke-width: 2; vector-effect: non-scaling-stroke; }
      .plot .bar { fill: Highlight; }
      .plot .baseline { stroke: color-mix(in srgb, CanvasText 45%, transparent); stroke-width: 1; vector-effect: non-scaling-stroke; }
      .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0; }
    </style>
    <main class="root"><p id="waiting">Waiting for a display mount.</p><figure hidden id="chart"><figcaption id="label"></figcaption><svg id="plot" class="plot" viewBox="0 0 100 100" preserveAspectRatio="none" aria-labelledby="label values"></svg><p class="sr-only" id="values"></p></figure></main>
    <script>
      const bridge = (message) => window.webkit?.messageHandlers?.hiboss?.postMessage(message);
      const prop = (definition, key, fallback) => definition[key] ?? fallback;
      const SVG_NS = 'http://www.w3.org/2000/svg';
      const validValues = (definition) => Array.isArray(definition.values) ? definition.values.filter((value) => value === null || (typeof value === 'number' && Number.isFinite(value))) : [];
      const scaleFor = (values) => {
        const numbers = values.filter((value) => value !== null);
        const minimum = Math.min(0, ...numbers);
        const maximum = Math.max(1, ...numbers);
        return { minimum, maximum, span: maximum - minimum || 1 };
      };
      const pointFor = (index, value, values, scale) => {
        const x = values.length > 1 ? 4 + (index * 92) / (values.length - 1) : 50;
        const y = 96 - ((value - scale.minimum) / scale.span) * 88;
        return `${x.toFixed(2)},${y.toFixed(2)}`;
      };
      function lineSegments(values, scale) {
        const segments = [];
        let segment = [];
        values.forEach((value, index) => {
          if (value === null) { if (segment.length) segments.push(segment); segment = []; return; }
          segment.push(pointFor(index, value, values, scale));
        });
        if (segment.length) segments.push(segment);
        return segments;
      }
      function drawPlot(type, values) {
        const plot = document.getElementById('plot');
        const scale = scaleFor(values);
        const baseline = document.createElementNS(SVG_NS, 'line');
        baseline.setAttribute('class', 'baseline'); baseline.setAttribute('x1', '4'); baseline.setAttribute('x2', '96'); baseline.setAttribute('y1', '96'); baseline.setAttribute('y2', '96');
        plot.replaceChildren(baseline);
        if (type === 'BarChart') {
          const width = Math.min(7, 70 / Math.max(values.length, 1));
          values.forEach((value, index) => {
            if (value === null) return;
            const point = pointFor(index, value, values, scale).split(',');
            const bar = document.createElementNS(SVG_NS, 'rect');
            bar.setAttribute('class', 'bar'); bar.setAttribute('x', `${Number(point[0]) - width / 2}`); bar.setAttribute('y', point[1]); bar.setAttribute('width', `${width}`); bar.setAttribute('height', `${Math.max(1, 96 - Number(point[1]))}`); plot.append(bar);
          });
          return;
        }
        lineSegments(values, scale).forEach((points) => {
          const path = document.createElementNS(SVG_NS, 'path');
          path.setAttribute('class', 'series'); path.setAttribute('d', points.map((point, index) => `${index ? 'L' : 'M'}${point}`).join(' ')); plot.append(path);
        });
      }
      function render(message) {
        const definition = message.definition || {};
        const values = validValues(definition);
        const type = definition.type === 'BarChart' ? 'BarChart' : 'LineChart';
        document.getElementById('waiting').hidden = true;
        document.getElementById('chart').hidden = false;
        document.getElementById('label').textContent = prop(definition, 'label', 'Line chart');
        document.getElementById('values').textContent = `${type === 'BarChart' ? 'Bar' : 'Line'} chart values: ${values.map((value) => value === null ? 'gap' : value).join(', ') || 'No values'}`;
        drawPlot(type, values);
        requestAnimationFrame(() => bridge({ kind: 'contentSizeChanged', panelId: message.panelId, contentHeight: Math.ceil(document.querySelector('.root').getBoundingClientRect().height) }));
      }
      window.__hibossBridge = { receive: (message) => message?.kind === 'mount' ? render(message) : bridge({ kind: 'renderFailed', panelId: message?.panelId || 'unknown', message: 'Malformed host message' }) };
    </script>
    """#
}
