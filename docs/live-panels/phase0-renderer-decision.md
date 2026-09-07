# Phase 0 renderer gate — evidence and open decision

Status: evidence complete, decision open. Date: 2026-09-07.
Inputs: [web spike](phase0-renderer-web.md), [SwiftUI spike](phase0-renderer-swiftui.md).
Contract at stake: [macOS native design contract](../macos-design-v2.md), rule 0.

Both spikes render the same two unmodified fixtures from `panel-runtime/fixtures/`.
Both live under `spikes/` and are deleted once this gate closes, so neither approach
gained an advantage from already being wired into a shipped target.

Every number below was reproduced by rebuilding and re-running each harness
independently of the agent that produced it. An earlier SwiftUI attempt was rejected
for reporting latency and memory that no code in it could have produced.

What "reproduced" means differs by measure, so it is stated exactly:

| Measure | Reproduction |
| --- | --- |
| Apply latency, both sides | Re-ran both harnesses; web p50 identical at 16.66 ms, SwiftUI within run-to-run variance |
| Cold mount, both sides | Same order and same ranking; absolute values move between runs |
| Memory, SwiftUI | The harness prints it; within one percent of the reported figures |
| Memory, web | Re-measured with `footprint` on both processes: 34 to 33 MB native, 21 to 20 MB WebKit, against 35 to 34 and 25 to 25 reported. Absolute values sit a few megabytes lower on this run; what reproduces is the absence of a measurable incremental cost, not the digits |
| Artifact size | The JavaScript payload matches exactly at 326,602 bytes; the native executable differs by 560 bytes across a rebuild |

Absolute memory and cold-mount figures are machine and run dependent. Treat the
rankings and the orders of magnitude as the evidence, not the individual digits.

## What each side measured

| | Bundled React in WKWebView | Bounded SwiftUI adapter |
| --- | --- | --- |
| Apply latency p50 / p95, n=200 | 16.66 / 17.40 ms | 0.288 / 0.651 ms (metric), 2.291 / 3.101 ms (rollout) |
| Reproduced | 16.66 / 16.81 ms | 0.261 / 0.679 ms, 2.210 / 2.999 ms |
| Cold mount | 10.34 ms (metric), 37.17 ms (rollout) | 112.42 ms (metric), 83.21 ms (rollout) |
| Reproduced | 12.83 ms | 99.77 ms, 72.53 ms |
| Memory | ≈0 MB incremental once WebKit is running; ~60 MB combined baseline | +23.9 MB first panel, +10.2 MB second, same process |
| Added artifact size | 326,602 B JavaScript payload, 655,464 B app total | native only |

## The latency figures are not comparable, and that is the first finding

The two harnesses stop the clock at different boundaries.

The web spike measures host → WebKit → React → layout → `requestAnimationFrame` →
bridge return. That path crosses one animation-frame boundary, which is why its p50
lands on 16.66 ms — the 60 Hz frame quantum. Its own document says the sample includes
that boundary. **The number is bounded below by the frame rate by construction.**

The SwiftUI spike stops at a SwiftUI `onChange` transaction observer, before anything
is presented. It excludes the equivalent boundary entirely.

So 16.66 against 0.29 is not "fifty times slower". It is two different measurements,
and no performance verdict is available from this data. The cold-mount comparison is
skewed the other way for the same class of reason: the web baseline was sampled after
the WebKit page had already initialized, while the SwiftUI figure includes AppKit and
SwiftUI first-window setup.

Neither approach has been shown to be too slow for this product. Latency should not
decide this gate.

## The asymmetry that actually matters

The argument for a native adapter is that the platform supplies keyboard focus,
appearance, text scaling and accessibility for free. That is rule 0 of the native
contract, and it is why this option is on the table at all.

**The SwiftUI spike did not test any of it.** All six qualitative observations —
input focus, text size, light/dark switching, VoiceOver, content height, and renderer
failure — are recorded as `not observed`, because its harness runs non-interactively.

The web spike did test most of them, including a real renderer kill (`kill -KILL` on
the WebContent process): the host survived, and the draft survived because the host
owns it rather than the web view. Its gap is VoiceOver, which it declined to claim
without running end to end.

So the axis most favourable to SwiftUI is the one with no SwiftUI evidence, and the
axis is the one this contract exists to protect. That is the honest state of the gate.

## What is settled

- **The bundling question is answered.** JavaScript enters a SwiftPM app bundle by
  being built by vite before SwiftPM compiles, copied into a resource target, and
  shipped in the nested resource bundle. No runtime download. The recurring costs are
  a Node toolchain in the build, a build-order dependency, and a resign step whenever
  the registry changes.
- **A generic native traversal is feasible but not cheap.** The SwiftUI spike is a real
  spec traversal, not per-fixture special cases, and it covers all eighteen catalog
  branches. It also reports its own limits: SwiftUI's statically typed `Table` column
  builder forces a generic adapter to collapse catalog columns into one, the JSON Schema
  subset is only partly implemented, and bindings need type erasure. Its own conclusion
  is that every future component carries native mapping, validation and accessibility work
  that the platform does not absorb.
- **Only five of the eighteen components are exercised by the current fixtures.** Both
  spikes are therefore evidence about a narrow slice: Stack, Metric, Select, NumberInput,
  Button. Charts, tables, and every text input are unproven on both sides.

## What is not settled

| Question | Why it is still open |
| --- | --- |
| Keyboard, focus, text scaling, VoiceOver on the native adapter | Never exercised; harness is non-interactive |
| VoiceOver on the web renderer | Semantics present, never run end to end |
| Whether web content is acceptable in this client at all | A contract decision, not a measurement |
| App Review exposure for bundled-code-plus-JSON | Flagged in the runtime design, unevaluated |

## Recommendation

Do not choose on this evidence. One narrow round closes the gate honestly: run both
spikes interactively and record keyboard traversal, focus rings, system text-size
changes, light/dark switching, and a VoiceOver pass over the rollout form and the chart.
That is the axis that decides this, it is cheap, and it is the only axis where the two
approaches genuinely differ on present evidence.

If the decision must be made now instead, the bundled React path is the only one proven
end to end — with the explicit understanding that adopting it is a deliberate exception
to rule 0 of the native contract, scoped to generated panel content, with navigation,
attribution, settings, errors and submission review staying native.

The exception must be written into the native contract before client UI work starts.
It is not granted by this document.

## Resolution — 2026-09-07

Neither renderer wins outright. The gate closes on a split by component class:
**anything the user types into or activates is native; only non-interactive display
components render in a web view.**

| Renderer | Components |
| --- | --- |
| Native SwiftUI | Stack, Grid, Section, Text, Metric, Progress, Status, TextInput, TextArea, NumberInput, Select, MultiSelect, Toggle, Slider, Button |
| Bundled web | LineChart, BarChart, Table |

The line follows the evidence rather than splitting the difference. The native spike's
only disclosed rendering hardships were charts and the `Table` it had to collapse into
a single column, because SwiftUI's statically typed column builder cannot express a
generic catalog table. Those are exactly the three components handed to the web
renderer. Everything the native spike rendered comfortably stays native.

Three consequences follow, and they are the reason this split is worth its cost:

1. **The native-contract exception shrinks to almost nothing.** It is no longer
   "generated content renders as web"; it is "a non-interactive display leaf may render
   in a web view". Every control, every piece of chrome, and all navigation stay native,
   which removes the cause of the verdict that ended the first native attempt.
2. **The decision path never touches web content.** Focus, keyboard traversal, VoiceOver
   over the form, validation errors, and submission review are entirely native. The web
   renderer cannot reach an answer, a draft, or a submission, so the bridge stops being
   part of the security boundary for decisions.
3. **The bridge collapses.** `draftChanged` and submission-bearing `actionRequested`
   disappear. What remains is `mount`, `applyTaskState`, `contentSizeChanged` and
   `renderFailed` — a display channel, not an interaction channel.

### What this decision introduces that neither pure option had

The seam. A web-rendered leaf inside a native panel raises questions that do not exist
in either single-renderer design, and none of them are answered by the spikes:

- Scroll ownership when a web leaf sits inside a native scroll view.
- Whether the native host can size the leaf correctly from `contentSizeChanged` while
  the surrounding native layout is also negotiating height.
- Keyboard traversal across the boundary: whether Tab enters the web leaf, and whether
  it can be kept out of the focus order entirely, which is what a display leaf wants.
- Appearance synchronisation when the system switches light/dark with a leaf mounted.
- VoiceOver traversal across the boundary in both directions.
- Behaviour when the web process dies while a native form above it holds a draft.

No production work starts until these are answered. The spikes stay until then.
