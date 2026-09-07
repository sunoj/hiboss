<!-- Agent guide to the reference panel fixtures and their authoring patterns. -->
<!-- Dependencies: panel-runtime catalog, protocol state ownership, and macOS demo captures. -->

# Live panel authoring examples

These fixtures are reference shapes, not a component gallery. Start with the example
whose task lifecycle matches the work you are publishing, then replace its labels,
bindings, values, and state schema with the task's real data.

## Choose a starting point

| Task shape | Start from | Pattern to preserve |
| --- | --- | --- |
| Long transfer or build with a known total | `download-progress.json` | A named stage, a fraction backed by completed/total work, and a throughput trend |
| Named end-to-end test suite | `e2e-test-run.json` | A display-only `Table` for each test plus passed, failed, running, and total counts |
| Bounded configuration sweep | `benchmark-sweep.json` | A native metric group for the winner and summary values plus a `BarChart` for comparisons |
| Continuous monitoring with no end | `service-monitor.json` | Stage, duration, observed values, and freshness; never invent completion |

The existing `mixed-panel.json` remains the starting point for an interactive decision
form. `metric-panel.json` is the smallest display-only smoke test, useful when the task
only has one scalar value.

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
all six fixtures. Final captures are in `screenshots/`:

- [mixed decision form](screenshots/panels-example-01-mixed.png)
- [metric smoke test](screenshots/panels-example-02-metric.png)
- [download progress](screenshots/panels-example-03-download-progress.png)
- [end-to-end test run](screenshots/panels-example-04-e2e-test-run.png)
- [benchmark sweep](screenshots/panels-example-05-benchmark-sweep.png)
- [service monitor](screenshots/panels-example-06-service-monitor.png)
- [service monitor dark-mode spot check](screenshots/panels-example-06-service-monitor-dark.png)

The first visual pass exposed two issues: new fixtures inherited the old “Metric
fixture” fallback title, and horizontal metric cells wrapped values and units. Both
were corrected before the final captures. The final light and dark panels showed the
expected charts, table, fraction, units, and monitor freshness without a synthetic
completion percentage. No keychain prompt appeared during this run; no password was
entered.
