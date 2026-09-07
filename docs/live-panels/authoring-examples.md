<!-- Agent guide to the reference panel fixtures and their authoring patterns. -->
<!-- Dependencies: panel-runtime catalog, protocol state ownership, and macOS demo captures. -->

# Live panel authoring examples

The catalog is the space an agent composes in. These examples are a handful of points
inside that space, not a menu or a boundary. Compose freely across the catalog: an agent
is expected to invent arrangements nobody has written down, and a panel that resembles
none of these examples is a success rather than a mistake.

## What these examples happen to demonstrate

| Example | What it happens to demonstrate | Pattern to preserve |
| --- | --- | --- |
| Long transfer or build with a known total | `download-progress.json` | A named stage, a fraction backed by completed/total work, and a throughput trend |
| Named end-to-end test suite | `e2e-test-run.json` | A display-only `Table` for each test plus passed, failed, running, and total counts |
| Bounded configuration sweep | `benchmark-sweep.json` | A native metric group for the winner and summary values plus a `BarChart` for comparisons |
| Continuous monitoring with no end | `service-monitor.json` | Stage, duration, observed values, and freshness; never invent completion |

`mixed-panel.json` happens to demonstrate an interactive decision form, while
`metric-panel.json` happens to be a smallest display-only smoke test for one scalar.
`research-intake.json` happens to combine free text, a longer text area, multiple
selection, a bounded slider, and submission. None of these arrangements is a template.

## The real boundaries

Guessing at the limits wastes authoring time, so the contracts are explicit:

- The component set is the 18 entries in `COMPONENT_TYPES` and their prop schemas in
  `panel-runtime/src/catalog.ts`, mirrored by the protocol in `docs/live-panels/protocol.md`.
- Supported expressions are `$state`, `$bindState`, `$item`, `$index`, and `$bindItem`,
  defined in `panel-runtime/src/catalog.ts` and checked in `panel-runtime/src/spec.ts`.
- The renderer split is implemented in `macos/Sources/HibossIsland/Panels/`: native
  controls live in `PanelRenderer.swift`; `Table`, `LineChart`, and `BarChart` are
  display-only web leaves in `PanelWebLeaf.swift`.
- Validation bounds are the catalog prop schemas plus the bounded answer-schema subset
  in `panel-runtime/src/answer-schema.ts`; tree element and depth limits are named in
  `panel-runtime/src/spec.ts`.

## Contract reminders

Every publication has a `stateSchema` for the object mounted at `/task`, and its
`initialState.task` must validate against that schema. Bind live producer values with
`$state` paths declared by the schema. Form answers are a separate `/form` draft and
are not part of the producer's task state.

The renderer split is deliberate: `Table`, `LineChart`, and `BarChart` are display-only
web leaves. They may receive rows or finite chart values, but they never contain an
input, button, action, or child control. `Stack`, `Grid`, `Section`, `Text`, `Metric`,
`Progress`, and `Status` remain native. Keep leaves at the edge of the tree.

## Two easy rules to get wrong

1. A gap is an explicit `null`, never a zero. A zero is an observed value and will draw
   a real point or bar. Use `null` when no sample exists or a series is discontinuous;
   the chart renderer preserves the break.

2. A task without a meaningful denominator does not get a percentage. Continuous work
   has no synthetic completion fraction. Show its stage, elapsed duration, current
   observations, and freshness instead, as `service-monitor.json` does. Use `Progress`
   only when the producer can explain what the numerator and denominator mean.

## Visual verification notes

The gated Panels destination was launched with `HIBOSS_PANELS_DEMO=1` and paged through
all seven fixtures. Final captures are in `screenshots/`:

- [mixed decision form](screenshots/panels-example-01-mixed.png)
- [metric smoke test](screenshots/panels-example-02-metric.png)
- [download progress](screenshots/panels-example-03-download-progress.png)
- [end-to-end test run](screenshots/panels-example-04-e2e-test-run.png)
- [benchmark sweep](screenshots/panels-example-05-benchmark-sweep.png)
- [service monitor](screenshots/panels-example-06-service-monitor.png)
- [service monitor dark-mode spot check](screenshots/panels-example-06-service-monitor-dark.png)
- [research intake](screenshots/panels-example-07-research-intake.png)

The first visual pass exposed two issues: new fixtures inherited the old “Metric
fixture” fallback title, and horizontal metric cells wrapped values and units. Both
were corrected before the final captures. The final light and dark panels showed the
expected charts, table, fraction, units, and monitor freshness without a synthetic
completion percentage. For the research intake pass, I typed into both native text
controls, selected multiple evidence options, moved the bounded confidence slider, and
submitted. The captured answer contained the entered fields, an array of stable option
ids, and the changed slider value. The final screenshot shows the native checkboxes and
slider on Example 7 of 7. No keychain prompt appeared during this run; no password was
entered.
