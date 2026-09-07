# Prior art for agent-authored live panels

Checked 2026-09-08, before continuing the iOS work. The question was whether someone has
already built what Live Panels is, and whether we should adopt it instead.

## What is actually out there

**A2UI** (`a2ui-project/a2ui`, Google, Apache-2.0, 16.3k stars, pushed 2026-09-05,
<https://a2ui.org/>) is the same idea by a different name: an agent emits a JSON component
tree, and the host renders it natively. v0.9.1 is Current; v1.0 is a release candidate. It
ships renderers for Swift (`A2UISwiftCore` / `A2UISwiftUI`, iOS 16+/macOS 14+), Kotlin,
Dart and the web, plus a conformance suite and versioned evolution guides. Third-party
renderers exist for Android Compose, React Native, .NET and iOS (`AGenUI`, 1.1k stars).

Its data model is ours:

- UI structure and application state are separate — components, then a data model.
- Component props bind to state by **JSON Pointer path** (RFC 6901): `{"path": "/user/name"}`.
- Updates stream as `updateDataModel {surfaceId, path, value}` into an **already-mounted**
  tree, explicitly so content changes "without regenerating it from scratch".

We arrived at the same three properties independently: a published spec, `/task/...` paths,
and relay patches that mutate a mounted tree. That convergence is the strongest evidence
we have that the shape is right.

## Where it stops, and why we keep ours

Two facts settle the adopt-or-keep question, both read from the repository rather than
from a summary:

1. **The BasicCatalog v1.0 has no charts.** Its 18 components are Text, Image, Icon, Video,
   AudioPlayer, Row, Column, List, Card, Tabs, Modal, Divider, Button, TextField, CheckBox,
   ChoicePicker, Slider, DateTimeInput. That is a form inside a conversation. Ours is a
   metric tile: charts and tables are the point, and they are the reason the renderer is
   split at all.
2. **There is no producer-authority model.** In the 1536-line v1.0 specification, `epoch`,
   `resync`, `concurren*`, `multiple agents`, `authority` and `persist` do not appear.
   A surface belongs to one agent for one conversation. Leases, epoch fencing, `baseSequence`
   checking, snapshot persistence and a wall fed by many agents at once are not questions it
   asks.

So adopting A2UI would mean replacing a catalog that has what we need with one that does
not, and rewriting the CLI validator, the server validation, `protocol.md` and every
published panel — to gain a renderer for components we do not use. Moving our own ~1500
platform-neutral lines into HibossKit is the cheaper path to the same place.

Worth revisiting if we ever want **interactive** panels. A2UI has thought about inputs,
actions and bidirectional binding, and we have deliberately kept the web leaves read-only
(`docs/macos-design-v2.md` §0.1).

## A caveat about how this was researched

A grounded web search returned three confident, plausible citations —
"Toward Frontier-Quality Declarative UI Generation at Small-Model Cost" (Sept 2026),
"EvoGenUI-Bench" (Aug 2026), "SchemaGUI" (Aug 2026) — with titles, dates and framing.
None of them can be found on arXiv. The first search that suggested this used a broken
query, which returned nothing for a control paper that certainly exists; over https the
control returns hits and these three still return none.

The engineering claims in the same summary (A2UI, its two schema modes, `@json-render/core`)
all checked out. Fabricated citations sat beside accurate engineering in one answer, so the
lesson is not "distrust the tool" but that a citation is not evidence until it resolves.
