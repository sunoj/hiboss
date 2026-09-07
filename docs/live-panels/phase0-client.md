# Phase 0 client surface

Date: 2026-09-07

The macOS client now has a `Panels` destination gated by `HIBOSS_PANELS_DEMO=1`.
The destination is fixture-driven and says so directly on screen: “Sample data —
fixture preview only; no live agent panel is connected.” It does not show agent
attribution, freshness, or connection state for the panel.

The mixed fixture renders its `Select`, `NumberInput`, and `Button` as native
SwiftUI controls. Typing into the traffic field updated local state and showed the
native focus ring. The Submit action is host-owned and formats the assembled `/form`
answer for review; it does not call a server. The metric fixture renders below it
as a native Metric component.

The chart is the only web leaf. It is a non-focusable `WKWebView` using the seam
bridge for mount, content height, and renderer failure. The light and dark captures
show the chart bars, label, and system-adaptive colours in both appearances. The
dark-mode check used System Events and was restored to the original light setting.

![Panels in light appearance](screenshots/panels-light.png)

![Panels in dark appearance](screenshots/panels-dark.png)

## What I saw

- The native form, chart, explicit sample-data note, and metric fixture were visible
  in the built app bundle.
- The chart initially rendered with a collapsed bar area during the first visual
  check. The leaf was missing the seam spike’s explicit chart height; adding that
  height and rebuilding fixed it. The final captures show the bars in both themes.
- The metric fixture begins below the visible fold at the default window size. It is
  still present in the native scroll view and can be reached by scrolling; this is
  expected content overflow, not clipping.
- No remaining visual defect was observed in the final light or dark captures.

Because the task red line keeps `Package.swift` and the build script unchanged, the
two approved fixture payloads are source-owned in `Panels/PanelFixtures.swift` so
the release bundle remains self-contained. Their catalog content is copied from
`panel-runtime/fixtures/mixed-panel.json` and `metric-panel.json` without adding a
runtime fetch or a publication claim.
