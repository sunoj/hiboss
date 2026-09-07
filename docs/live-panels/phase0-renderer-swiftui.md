# Phase 0D — bounded SwiftUI panel adapter

Date: 2026-09-07  
Scope: throwaway spike only. The source reads the repository fixtures; it does not copy or modify them.

## What was built

A standalone macOS SwiftUI executable under `spikes/panel-swiftui/`. `PanelRenderer`
traverses `root`, resolves child IDs, and dispatches on catalog component type. It is a
general adapter: fixtures are not special-cased.

Supported expressions: `$state`, `$bindState`, `$item`, `$index`, `$bindItem`, plus bounded
`$cond` visibility (`path`/`value`). Structural `repeat` requires a stable item `id` (or the
declared `itemKey`); non-identifiable items are omitted rather than given unstable generated
IDs. Expanding a repeat re-enters the same element with `expandRepeat: false` so the template
body renders once per item without infinite recursion.

Inputs write through `PanelStore` bindings into `/form` (and host deltas into `/task`).
`submitRequest` validates the `/form` object against the fixture `answerSchema` before
reporting success; `openPanel` is registered and reports its panel ID. The validator covers
the schema keywords needed by the rollout fixture: object `properties`, `required`,
`additionalProperties`, `type`, `enum`, `minimum`, `maximum`, and the fixture's bounded
`allOf`/`if`/`then` rule. It does not implement the full protocol subset (`minLength`, array
constraints, `$defs`/`$ref`, or producer `stateSchema` validation).

All 18 catalog component branches exist in the switch: Stack, Grid, Section, Text, Metric,
Progress, Status, Table, LineChart, BarChart, TextInput, TextArea, NumberInput, Select,
MultiSelect, Toggle, Slider, and Button. The two supplied fixtures exercise only **5 of 18**:
Stack, Metric, Select, NumberInput, and Button. Grid, Section, Text, Progress, Status, Table,
both charts, TextInput, TextArea, MultiSelect, Toggle, Slider, repeat, conditional visibility,
and `openPanel` were **not exercised** by either fixture.

Native mapping choices: Select → `Picker`, Toggle → `Toggle`, Slider → `Slider`, Table →
SwiftUI `Table`, text → semantic styles (`.title2`, `.headline`, `.callout`, …), colour →
AppKit/SwiftUI semantic colours only (no hex, no `.system(size:)`).

### LineChart cost

`LineChart` uses Swift Charts (`LineMark`). Explicit JSON nulls split the series into separate
runs so gaps stay gaps, never zeros. A DisclosureGroup titled "Chart values" lists each sample
as a non-visual alternative. Implementing that path took roughly one focused component section
(~40 lines) plus Charts linkage; the hard parts were null-to-gap splitting and accepting that
Swift Charts still needs a textual fallback for VoiceOver. **Neither fixture contains a
chart**, so this path was compiled and reviewed, not fixture-exercised. Further chart work
(axes, multiple series, live `$state` arrays under load) would be another half-day per
concern, not a free Chart wrapper.

### Table limitation

SwiftUI `Table` has a statically typed column builder. The generic adapter therefore renders
catalog columns as **one** native `Table` column whose cells join declared values with
slashes. That is a real catalog-to-SwiftUI impedance mismatch, not a hidden special case.

### Catalog coverage summary

| Layer | Coverage |
| --- | --- |
| Code paths present | 18 / 18 components |
| Fixture-exercised | 5 / 18 components |
| Incomplete semantics | Table column builder; schema subset; chart live-binding not fixture-proven |

Per further component beyond the stubs: expect mapping + binding + a11y label + validation
hooks + a measurement sample — typically a few dozen lines, not a one-liner JSON switch.

## Measurement method

Run from the repository root:

```sh
swift build --package-path spikes/panel-swiftui
spikes/panel-swiftui/.build/arm64-apple-macosx/debug/PanelSwiftUISpike --measure
```

The harness creates an `NSHostingView` for each fixture in a zero-alpha, mouse-ignoring
window ordered front regardless of focus. Cold mount starts immediately before hosting and
ends on the next main-queue turn after `layoutSubtreeIfNeeded` / `displayIfNeeded`.

Each of 200 host deltas records `DispatchTime.now().uptimeNanoseconds` immediately before
`PanelStore.applyHostDelta`. **Applied** is observed as the next main-queue turn after that
write, after `layoutSubtreeIfNeeded` on the hosting view. The code comments state this
boundary explicitly; it is not a Core Animation commit probe. P50 / P95 use linear
interpolation over the sorted raw samples. Footprint uses Mach `resident_size` before
hosting and after the interactive boundary.

### Captured stdout from `spikes/panel-swiftui/.build/arm64-apple-macosx/debug/PanelSwiftUISpike --measure`

Command (repository root, 2026-09-07):

```sh
spikes/panel-swiftui/.build/arm64-apple-macosx/debug/PanelSwiftUISpike --measure
```

```text
fixture=metric-panel.json
measurement_status=ok
cold_mount_ms=112.421
footprint_before_bytes=30244864
footprint_after_bytes=54149120
apply_ms[1]=5.186
apply_ms[2]=4.859
apply_ms[3]=0.921
apply_ms[4]=0.428
apply_ms[5]=0.351
apply_ms[6]=0.307
apply_ms[7]=0.295
apply_ms[8]=0.284
apply_ms[9]=0.285
apply_ms[10]=0.651
apply_ms[11]=0.837
apply_ms[12]=0.742
apply_ms[13]=0.353
apply_ms[14]=0.324
apply_ms[15]=0.309
apply_ms[16]=0.299
apply_ms[17]=0.294
apply_ms[18]=0.300
apply_ms[19]=0.303
apply_ms[20]=0.297
apply_ms[21]=0.288
apply_ms[22]=0.295
apply_ms[23]=0.287
apply_ms[24]=0.290
apply_ms[25]=0.304
apply_ms[26]=0.288
apply_ms[27]=0.288
apply_ms[28]=0.288
apply_ms[29]=0.287
apply_ms[30]=0.301
apply_ms[31]=0.300
apply_ms[32]=0.297
apply_ms[33]=0.816
apply_ms[34]=0.558
apply_ms[35]=0.323
apply_ms[36]=0.303
apply_ms[37]=0.304
apply_ms[38]=0.298
apply_ms[39]=0.288
apply_ms[40]=0.284
apply_ms[41]=0.297
apply_ms[42]=0.285
apply_ms[43]=0.289
apply_ms[44]=0.283
apply_ms[45]=0.284
apply_ms[46]=0.280
apply_ms[47]=0.291
apply_ms[48]=0.279
apply_ms[49]=0.282
apply_ms[50]=0.283
apply_ms[51]=0.292
apply_ms[52]=0.285
apply_ms[53]=0.283
apply_ms[54]=0.281
apply_ms[55]=0.280
apply_ms[56]=0.282
apply_ms[57]=0.282
apply_ms[58]=0.285
apply_ms[59]=0.278
apply_ms[60]=0.283
apply_ms[61]=0.277
apply_ms[62]=0.280
apply_ms[63]=0.286
apply_ms[64]=0.279
apply_ms[65]=0.284
apply_ms[66]=0.287
apply_ms[67]=0.284
apply_ms[68]=0.281
apply_ms[69]=0.279
apply_ms[70]=0.287
apply_ms[71]=0.279
apply_ms[72]=0.279
apply_ms[73]=0.280
apply_ms[74]=0.288
apply_ms[75]=0.281
apply_ms[76]=0.282
apply_ms[77]=0.280
apply_ms[78]=0.282
apply_ms[79]=0.278
apply_ms[80]=0.284
apply_ms[81]=0.288
apply_ms[82]=0.280
apply_ms[83]=0.283
apply_ms[84]=0.276
apply_ms[85]=0.280
apply_ms[86]=0.276
apply_ms[87]=0.282
apply_ms[88]=0.277
apply_ms[89]=0.653
apply_ms[90]=0.490
apply_ms[91]=0.304
apply_ms[92]=0.312
apply_ms[93]=0.290
apply_ms[94]=0.291
apply_ms[95]=0.288
apply_ms[96]=0.285
apply_ms[97]=0.284
apply_ms[98]=0.278
apply_ms[99]=0.281
apply_ms[100]=0.525
apply_ms[101]=0.330
apply_ms[102]=0.312
apply_ms[103]=0.297
apply_ms[104]=0.294
apply_ms[105]=0.297
apply_ms[106]=0.293
apply_ms[107]=0.294
apply_ms[108]=0.297
apply_ms[109]=0.291
apply_ms[110]=0.286
apply_ms[111]=0.812
apply_ms[112]=0.712
apply_ms[113]=0.346
apply_ms[114]=0.314
apply_ms[115]=0.302
apply_ms[116]=0.294
apply_ms[117]=0.294
apply_ms[118]=0.294
apply_ms[119]=0.307
apply_ms[120]=0.297
apply_ms[121]=0.288
apply_ms[122]=0.292
apply_ms[123]=0.287
apply_ms[124]=0.290
apply_ms[125]=0.286
apply_ms[126]=0.294
apply_ms[127]=0.285
apply_ms[128]=0.287
apply_ms[129]=0.288
apply_ms[130]=0.288
apply_ms[131]=0.286
apply_ms[132]=0.284
apply_ms[133]=0.287
apply_ms[134]=0.287
apply_ms[135]=0.289
apply_ms[136]=0.284
apply_ms[137]=0.286
apply_ms[138]=0.285
apply_ms[139]=0.287
apply_ms[140]=0.818
apply_ms[141]=0.563
apply_ms[142]=0.335
apply_ms[143]=0.308
apply_ms[144]=0.295
apply_ms[145]=0.293
apply_ms[146]=0.294
apply_ms[147]=0.288
apply_ms[148]=0.294
apply_ms[149]=0.290
apply_ms[150]=0.292
apply_ms[151]=0.285
apply_ms[152]=0.291
apply_ms[153]=0.286
apply_ms[154]=0.289
apply_ms[155]=0.286
apply_ms[156]=0.289
apply_ms[157]=0.291
apply_ms[158]=0.287
apply_ms[159]=0.286
apply_ms[160]=0.287
apply_ms[161]=0.288
apply_ms[162]=0.284
apply_ms[163]=0.284
apply_ms[164]=0.286
apply_ms[165]=0.289
apply_ms[166]=0.285
apply_ms[167]=0.286
apply_ms[168]=0.287
apply_ms[169]=0.283
apply_ms[170]=0.287
apply_ms[171]=0.287
apply_ms[172]=0.283
apply_ms[173]=0.287
apply_ms[174]=0.283
apply_ms[175]=0.284
apply_ms[176]=0.280
apply_ms[177]=0.283
apply_ms[178]=0.285
apply_ms[179]=0.283
apply_ms[180]=0.287
apply_ms[181]=0.280
apply_ms[182]=0.286
apply_ms[183]=0.282
apply_ms[184]=0.284
apply_ms[185]=0.284
apply_ms[186]=0.284
apply_ms[187]=0.280
apply_ms[188]=0.285
apply_ms[189]=0.288
apply_ms[190]=0.282
apply_ms[191]=0.287
apply_ms[192]=0.290
apply_ms[193]=0.286
apply_ms[194]=0.281
apply_ms[195]=0.647
apply_ms[196]=0.551
apply_ms[197]=0.321
apply_ms[198]=0.308
apply_ms[199]=0.294
apply_ms[200]=0.291
apply_samples=200
apply_p50_ms=0.288
apply_p95_ms=0.651
fixture=rollout-decision.json
measurement_status=ok
cold_mount_ms=83.213
footprint_before_bytes=54673408
footprint_after_bytes=64864256
apply_ms[1]=5.256
apply_ms[2]=3.094
apply_ms[3]=3.289
apply_ms[4]=3.294
apply_ms[5]=2.711
apply_ms[6]=2.715
apply_ms[7]=2.452
apply_ms[8]=2.282
apply_ms[9]=2.909
apply_ms[10]=3.315
apply_ms[11]=2.609
apply_ms[12]=2.513
apply_ms[13]=2.537
apply_ms[14]=2.410
apply_ms[15]=2.991
apply_ms[16]=3.147
apply_ms[17]=2.531
apply_ms[18]=2.257
apply_ms[19]=2.350
apply_ms[20]=2.250
apply_ms[21]=2.276
apply_ms[22]=2.922
apply_ms[23]=3.064
apply_ms[24]=2.370
apply_ms[25]=2.499
apply_ms[26]=2.305
apply_ms[27]=2.244
apply_ms[28]=2.796
apply_ms[29]=2.921
apply_ms[30]=2.539
apply_ms[31]=2.305
apply_ms[32]=2.277
apply_ms[33]=2.227
apply_ms[34]=2.178
apply_ms[35]=2.675
apply_ms[36]=2.778
apply_ms[37]=2.352
apply_ms[38]=2.254
apply_ms[39]=2.254
apply_ms[40]=2.215
apply_ms[41]=2.222
apply_ms[42]=5.181
apply_ms[43]=3.716
apply_ms[44]=3.049
apply_ms[45]=2.820
apply_ms[46]=2.615
apply_ms[47]=2.984
apply_ms[48]=2.892
apply_ms[49]=2.366
apply_ms[50]=2.281
apply_ms[51]=2.238
apply_ms[52]=2.212
apply_ms[53]=2.757
apply_ms[54]=2.849
apply_ms[55]=2.307
apply_ms[56]=2.188
apply_ms[57]=2.143
apply_ms[58]=2.146
apply_ms[59]=2.170
apply_ms[60]=2.697
apply_ms[61]=2.674
apply_ms[62]=2.345
apply_ms[63]=2.240
apply_ms[64]=2.178
apply_ms[65]=2.197
apply_ms[66]=2.141
apply_ms[67]=2.889
apply_ms[68]=4.295
apply_ms[69]=3.085
apply_ms[70]=2.767
apply_ms[71]=2.599
apply_ms[72]=2.388
apply_ms[73]=2.919
apply_ms[74]=3.071
apply_ms[75]=2.487
apply_ms[76]=2.339
apply_ms[77]=2.268
apply_ms[78]=2.255
apply_ms[79]=2.797
apply_ms[80]=2.961
apply_ms[81]=2.411
apply_ms[82]=2.271
apply_ms[83]=2.229
apply_ms[84]=2.226
apply_ms[85]=2.208
apply_ms[86]=2.668
apply_ms[87]=3.011
apply_ms[88]=2.390
apply_ms[89]=2.245
apply_ms[90]=2.202
apply_ms[91]=2.163
apply_ms[92]=2.143
apply_ms[93]=2.630
apply_ms[94]=2.766
apply_ms[95]=2.274
apply_ms[96]=2.248
apply_ms[97]=2.206
apply_ms[98]=2.227
apply_ms[99]=2.188
apply_ms[100]=3.099
apply_ms[101]=3.014
apply_ms[102]=3.242
apply_ms[103]=2.736
apply_ms[104]=2.565
apply_ms[105]=2.425
apply_ms[106]=2.848
apply_ms[107]=2.646
apply_ms[108]=2.220
apply_ms[109]=2.187
apply_ms[110]=2.174
apply_ms[111]=2.177
apply_ms[112]=2.194
apply_ms[113]=2.742
apply_ms[114]=2.568
apply_ms[115]=2.227
apply_ms[116]=2.176
apply_ms[117]=2.203
apply_ms[118]=2.175
apply_ms[119]=2.136
apply_ms[120]=2.584
apply_ms[121]=2.610
apply_ms[122]=2.394
apply_ms[123]=2.180
apply_ms[124]=2.189
apply_ms[125]=2.137
apply_ms[126]=2.164
apply_ms[127]=2.125
apply_ms[128]=2.589
apply_ms[129]=2.586
apply_ms[130]=2.222
apply_ms[131]=2.096
apply_ms[132]=2.101
apply_ms[133]=2.142
apply_ms[134]=2.198
apply_ms[135]=2.558
apply_ms[136]=2.499
apply_ms[137]=2.163
apply_ms[138]=2.096
apply_ms[139]=2.084
apply_ms[140]=2.077
apply_ms[141]=2.063
apply_ms[142]=2.577
apply_ms[143]=2.485
apply_ms[144]=2.129
apply_ms[145]=2.077
apply_ms[146]=2.064
apply_ms[147]=2.116
apply_ms[148]=2.076
apply_ms[149]=2.140
apply_ms[150]=2.660
apply_ms[151]=2.530
apply_ms[152]=2.180
apply_ms[153]=2.107
apply_ms[154]=2.101
apply_ms[155]=2.078
apply_ms[156]=2.069
apply_ms[157]=2.562
apply_ms[158]=2.480
apply_ms[159]=2.259
apply_ms[160]=2.075
apply_ms[161]=2.066
apply_ms[162]=2.084
apply_ms[163]=2.091
apply_ms[164]=2.069
apply_ms[165]=2.601
apply_ms[166]=2.475
apply_ms[167]=2.133
apply_ms[168]=2.085
apply_ms[169]=2.071
apply_ms[170]=2.075
apply_ms[171]=2.070
apply_ms[172]=2.566
apply_ms[173]=2.558
apply_ms[174]=2.205
apply_ms[175]=2.097
apply_ms[176]=2.059
apply_ms[177]=2.050
apply_ms[178]=2.059
apply_ms[179]=2.074
apply_ms[180]=2.571
apply_ms[181]=2.541
apply_ms[182]=2.092
apply_ms[183]=2.044
apply_ms[184]=2.043
apply_ms[185]=2.072
apply_ms[186]=2.059
apply_ms[187]=2.058
apply_ms[188]=2.535
apply_ms[189]=2.506
apply_ms[190]=2.123
apply_ms[191]=2.059
apply_ms[192]=3.748
apply_ms[193]=2.730
apply_ms[194]=3.087
apply_ms[195]=2.997
apply_ms[196]=2.508
apply_ms[197]=2.312
apply_ms[198]=2.324
apply_ms[199]=2.300
apply_ms[200]=2.271
apply_samples=200
apply_p50_ms=2.291
apply_p95_ms=3.101

```

## Observations

- **Input focus** — not observed. Keyboard reach, focus ring, Tab, Shift-Tab, Command-A,
  Command-C, and Escape were not tested in an interactive session.
- **Text size** — not observed. System text-size and accessibility changes were not tested
  against a live window.
- **Appearance** — not observed. Light/dark switching while open was not tested.
- **VoiceOver** — not observed. Field labels, validation errors, chart values, and the chart
  disclosure were not exercised with VoiceOver. The disclosure exists in code as a fallback;
  that is not the same as observing it under VoiceOver.
- **Content height** — not observed. The spike wraps content in `ScrollView`; no host
  natural-height preference or fitting-size measurement was taken.
- **Failure** — not observed. No draft was half-typed while breaking the renderer, and no
  navigation/recovery run was completed.

## Decision note

The one thing I would tell someone choosing between the approaches: a bounded native catalog
buys platform focus, appearance, and control behaviour only after you accept a real adapter
layer — bindings, schema validation, and per-component native mapping — not a mechanical
JSON-to-SwiftUI conversion.

The strongest argument **against** this approach is exactly that cost curve. Runtime bindings
need type erasure (`AnyView` / dynamic `JSONValue`), answer validation is a second schema
implementation to keep in lockstep with the server, and SwiftUI's static builders force
compromises such as the single-column `Table`. Every new catalog component still needs native
mapping, accessibility, validation, and measurement — the platform does not absorb that work
for free.
