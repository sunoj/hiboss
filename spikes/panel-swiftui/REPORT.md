# Phase 0D — bounded SwiftUI panel adapter

Date: 2026-09-07  
Scope: throwaway spike only. The source reads the repository fixtures; it does not copy or modify them.

## What was built

The package is a standalone macOS SwiftUI executable. PanelRenderer traverses root,
resolves child IDs, and dispatches on the catalog component type. It supports the five
expressions in the protocol ($state, $bindState, $item, $index, $bindItem), simple
bounded $cond visibility, and structural repeats. Repeated items require an id (or the
declared item key) and use that value as the SwiftUI ForEach identity; non-identifiable
items are omitted rather than given an unstable generated ID.

Inputs write through PanelStore bindings. submitRequest validates the /form object
against the fixture answer schema before reporting success; openPanel is registered and
reports its panel ID. The validator covers the schema keywords needed by the rollout
fixture: object properties, required, additionalProperties, type, enum, minimum, maximum,
and the fixture's bounded allOf/if/then rule.

All 18 catalog component branches are present: Stack, Grid, Section, Text, Metric, Progress,
Status, Table, LineChart, BarChart, TextInput, TextArea, NumberInput, Select, MultiSelect,
Toggle, Slider, and Button. The two fixtures exercise only 5 of 18: Stack, Metric, Select,
NumberInput, and Button. Grid, Section, Text, Progress, Status, Table, both charts, TextInput,
TextArea, MultiSelect, Toggle, Slider, repeat, conditional visibility, and openPanel were
not exercised by either supplied fixture.

Select is Picker, Toggle is Toggle, Slider is Slider, Table is SwiftUI Table, text uses
semantic styles, and colours use AppKit/SwiftUI semantic colours. Charts use Swift Charts.
LineChart splits values at explicit nulls, so a null creates a gap rather than a zero. It
also exposes a visible “Chart values” disclosure as a non-visual alternative. SwiftUI
Table has a statically typed column builder; the generic adapter therefore renders catalog
columns as one native Table column whose cells contain the declared values separated by
slashes. That is a measurable limitation, not a hidden special case.

The catalog coverage is therefore 18/18 code paths, 5/18 fixture coverage, and incomplete
catalog semantics in the generic Table representation. The adapter does not implement the
full protocol JSON Schema subset (minLength, array constraints, $defs/$ref, or server
state-schema validation); those would be further work per component/schema feature.

## Measurement method

Run from the repository root:

~~~sh
swift build --package-path spikes/panel-swiftui
spikes/panel-swiftui/.build/arm64-apple-macosx/debug/PanelSwiftUISpike --measure
~~~

The harness creates an NSHostingView for each fixture in a zero-alpha, mouse-ignoring
window. Cold mount starts immediately before hosting and would end after layout plus a main
queue turn. Before each host delta it records DispatchTime.now().uptimeNanoseconds;
PanelStore increments revision, and the root view's SwiftUI onChange(of:revision)
transaction observer is the “applied” boundary. It would collect 200 samples per fixture.
P50 and p95 use linear interpolation over the sorted raw samples. Footprint uses Mach
resident_size before hosting and after the interactive boundary.

### Captured stdout from spikes/panel-swiftui/.build/arm64-apple-macosx/debug/PanelSwiftUISpike --measure

~~~text
fixture=metric-panel.json
measurement_status=not measured (AppKit window did not become interactive within 5 seconds)
cold_mount_ms=not measured
footprint_before_bytes=not measured
footprint_after_bytes=not measured
apply_samples=0
apply_p50_ms=not measured
apply_p95_ms=not measured
fixture=rollout-decision.json
measurement_status=not measured (AppKit window did not become interactive within 5 seconds)
cold_mount_ms=not measured
footprint_before_bytes=not measured
footprint_after_bytes=not measured
apply_samples=0
apply_p50_ms=not measured
apply_p95_ms=not measured
~~~

This terminal environment did build the executable, but AppKit did not make the hidden
window interactive. The bounded fallback emitted the output above and exited with status
0. No latency, cold-mount, or footprint number is claimed.

## Observations

- Input focus — not observed. Keyboard reach, focus ring, Tab, Shift-Tab, Command-A,
  Command-C, and Escape were not tested because no interactive window became available.
- Text size — not observed. System text-size and accessibility changes were not tested.
- Appearance — not observed. Light/dark switching while open was not tested.
- VoiceOver — not observed. Field labels, validation errors, chart values, and the chart
  alternative were not tested with VoiceOver.
- Content height — not observed. The spike uses a ScrollView; no host natural-height
  measurement was taken.
- Failure — not observed. No draft was half-typed while breaking the renderer, and no
  navigation/recovery run was completed.

## Decision note

The one thing I would tell a chooser: a bounded native catalog can buy focus, accessibility,
appearance, and keyboard behavior from the platform, but only after building and maintaining
a real adapter layer for every component and binding.

The strongest argument against this approach is that the work is not JSON-to-SwiftUI
conversion: runtime bindings need type erasure, schema validation needs a second
implementation, and SwiftUI's static builders create generic-component compromises such as
the Table limitation. Every new catalog component also needs native mapping, validation,
accessibility, and measurement coverage.
