# Panels dashboard UI

The macOS Panels wall and iOS Home wall share `PanelDashboardCard`. The visual
reference combines Fitness-style rounded surfaces, prominent values and progress
rings with the readable charts and table summaries of an operations dashboard.
Appearance follows the system; navigation and activation remain native.

## Content and layout

- Metrics follow the authored tree order, with explicit summary bindings first.
- A ring requires a Progress component with a valid range and current value.
  Monitoring panels never acquire an inferred completion percentage.
- Wall charts use Swift Charts; missing samples break lines and remain explicit
  in their accessibility values. Full detail retains the existing web display leaves.
- Table previews show three columns and two rows, with the remaining row count.
- Form previews summarize fields. Opening a card reveals the existing full renderer.
  Form submission behavior remains local capture, with the captured answer visible.
- Every card includes its producer and host-owned freshness. Cached and offline
  content retain those states instead of being presented as live.
- Columns expand to use the available width. Compact cards can share a phone row;
  charts span two columns. Placement depends on identity, authored size, and width,
  never on changing producer data.
- Numeric and progress updates animate in place. Reduce Motion disables these
  animations; Increase Contrast adds a visible tile boundary.

## Verification

`PanelDashboardFlowTests` covers live snapshot updates during detail navigation,
authored metric order, meaningful progress, chart gaps, phone packing, and native
rendering in both appearances. `PanelWallLayoutTests` covers stable placement.

```sh
swift test --package-path macos
swift test --package-path HibossKit
HIBOSS_PANEL_SNAPSHOTS=/private/tmp swift test --package-path macos --filter PanelDashboardFlowTests
```

The snapshot flag writes `dashboard-dark.png` and `dashboard-light.png` into an
existing directory. These are native component renders using local sample data,
not screenshots of a connected production dashboard.

[Dark preview](screenshots/panels-v2-dark.png) ·
[Light preview](screenshots/panels-v2-light.png)
