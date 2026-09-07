# Live Panels and Interactive Requests

Status: design proposal; implementation has not started.
Date: 2026-09-07.
Scope: agent-authored dashboards, questionnaires, and interactive decisions in HiBoss.

## 1. Purpose and document map

Give a continuing agent task a persistent visual surface. An agent declares the
layout, binds it to changing data, and requests structured human input when needed.
The same task can move from a questionnaire to live progress to a final report.

This document records the complete planning baseline. All new APIs, commands,
components, storage entities, and package paths below are **proposed**, not shipped.
Writing this plan does not authorize implementation, dependency installation,
database changes, deployment, or a release.

| Document | Responsibility |
| --- | --- |
| [This design](live-panels-design.md) | Product model, scope, user experience, decisions |
| [Protocol](live-panels/protocol.md) | Publication, state, forms, submissions, API contracts |
| [Runtime and transport](live-panels/runtime.md) | Renderers, relay, P2P, persistence, trust boundaries |
| [Delivery plan](live-panels/rollout.md) | Work packages, verification, budgets, gates, open decisions |

If details conflict, the protocol owns wire semantics, the runtime document owns
transport behavior, and this document owns product behavior. Resolve discrepancies
in the design before implementation; do not choose whichever is easier to code.

## 2. Product outcomes

1. A boss can identify what needs a decision before browsing task progress.
2. Agents can compose task-specific interfaces without generating executable code.
3. A published panel updates in place while a task continues.
4. Questionnaires return typed answers with an explicit submission receipt.
5. iOS and macOS show the same task and decision state across devices.
6. Closing an app or disconnecting a producer does not erase the latest saved view.
7. The UI clearly distinguishes a running task, stale data, and a resolved request.

### Representative journeys

| Journey | Example | Completion condition |
| --- | --- | --- |
| Bounded work | Run 24 benchmark configurations | Final metrics and report remain readable |
| Continuous monitoring | Watch a service's throughput and errors | Current values and freshness remain visible |
| Intake questionnaire | Choose research scope, constraints, and output | Agent receives one validated answer object |
| Complex choice | Compare three plans and adjust resource limits | Selection and parameters are submitted together |
| Batch review | Accept, reject, or annotate candidate results | Stable item IDs identify every submitted decision |
| Mixed task | Intake, execution, intervention, final report | One panel links all requests and outcomes |

A continuous task has no synthetic completion percentage. Show a stage, duration,
observed values, and freshness unless the producer supplies a meaningful denominator.

## 3. Current repository baseline

These observations describe the inspected working tree, including ongoing local
macOS work. They are not claims about what is deployed in production.

| Existing area | Evidence | Consequence |
| --- | --- | --- |
| Attention-first home | [Shared attention contract](native-client-attention-model.md), [iOS HomeView](../ios/App/Home/HomeView.swift) | Panels must not push actionable requests below passive metrics |
| macOS overview | [Overview design](macos-information-redesign.md) | Preserve category/count agreement and navigation behavior |
| Native UI | [macOS native contract](macos-design-v2.md) | Web content inside native clients needs an explicit design boundary |
| Session history | [Session contract](session-stream-contract.md), [server route](../server/src/routes/session-events.ts) | Existing SSE reads D1; add a separate live-state path |
| Structured choices | [Option claim](../server/src/routes/boss-option-reply.ts) | Reuse resolution principles, not string-only answer storage |
| Signing | [Signing design](message-signing.md) | New structured answers require a purpose-specific signed payload |
| Native summaries | [Activity attributes](../ios/Shared/DecisionActivity.swift) | Task summaries need their own compact contract |
| Desktop overlay | [Panel controller](../macos/Sources/HibossIsland/IslandPanelController.swift) | AppKit window behavior is reusable; edge docking is new |
| Agent entry points | [CLI](../cli/src/commands), [MCP bridge](../mcp/server.ts) | Provide the same panel operations through both interfaces |
| Progress feed | [Feed contract](progress-feed-v2-contract.md) | Live ticks are not progress posts and never create feed noise |

## 4. Proposed decisions

| Decision | Planning baseline | Reason |
| --- | --- | --- |
| Authoring | json-render JSON spec constrained to a HiBoss catalog | Reuse an existing language and validation model |
| Component implementation | HiBoss-owned, bundled React registry for the first renderer evaluation | Reuse the official renderer without running agent TSX |
| Full native rendering | A bounded SwiftUI adapter is an alternative evaluated before production | Respect existing native controls and accessibility requirements |
| State | Separate producer data, user drafts, and host-owned metadata | Updates cannot overwrite input or forge resolution |
| Live transport | Worker + Durable Object WebSocket relay first | Straightforward outbound connections and device fan-out |
| Direct transport | Optional later WebRTC DataChannel + TURN | Adopt only if measurements or explicit privacy requirements justify it |
| Formal answers | Durable authenticated HTTPS submission with idempotency | An answer must survive connection loss and producer downtime |
| System surfaces | Native summary and deep link | A full generated form does not fit a Live Activity |
| Data retention | Latest saved state and durable decisions; bounded telemetry window | Recoverable panels without storing every sample forever |
| Arbitrary code | Outside the initial scope | json-render catalog composition is the intended extension mechanism |

These are recommendations for future work, not claims of user approval for a
specific implementation. Exact dependency versions and performance budgets must
be established by the evaluation gates in the delivery plan.

### Why json-render

The project separates a typed component/action catalog, an agent-generated spec,
and a registry of concrete implementations. This directly supports our proposed
agent authoring interface. [json-render introduction](https://json-render.dev/docs)

State bindings and conditional visibility let a layout react to task values and
form answers. We will keep the upstream syntax inside the spec and add HiBoss
lifecycle metadata outside it. [Data binding](https://json-render.dev/docs/data-binding),
[visibility](https://json-render.dev/docs/visibility)

This is compositional openness: agents choose arrangements and registered
capabilities. A component the client has never shipped cannot appear merely
because an agent invents its name. Complex new visualizations require a catalog
extension and a corresponding bundled implementation.

## 5. Domain model

**LivePanel** is the stable task surface. Its identity survives layout revisions,
producer reconnections, and successive agent sessions. A session association is
useful context, not the panel's lifetime or authorization boundary.

**PanelDefinition** is an immutable published revision: catalog version, UI spec,
producer-state schema, initial state, and compact summary bindings.

**PanelState** is the latest accepted producer snapshot and its ordered updates.
Time-series data is a bounded display window, not an implied telemetry archive.

**InteractionRequest** is an immutable question revision attached to a panel. It
includes a form spec, answer schema, frozen decision context, intent, and deadline.
One panel may contain several requests, each with its own independent resolution.

**Submission** is an immutable accepted answer with actor provenance, request
revision, idempotency identity, and delivery status. It is distinct from the
agent's later execution or acknowledgement of that answer.

**User preferences and drafts** belong to the user. Pins and ordering may sync;
drafts remain device-local in the initial release. Agents cannot overwrite either.

## 6. UI behavior

### iOS

- Home begins with the existing attention model, extended to include unresolved
  blocking forms. Waiting forms count once by request ID, even if linked in a panel.
- A running/paused/pinned panel section follows attention. Stable ordering avoids
  jumping cards on every update. User pin order precedes normal activity ordering.
- Compact previews show title, attribution, stage, key values, and freshness.
  Open detail for forms, large charts, comparisons, and batch review.
- Keep the native navigation bar and request identity visible. Long forms use a
  scrollable body with a reachable submit area above the keyboard.
- Initial loading, cached stale content, disconnected, incompatible catalog,
  invalid spec, and renderer failure have distinct presentations.
- VoiceOver exposes chart summaries and a data-table alternative. Type scaling,
  reduced motion, contrast, and touch target checks apply to generated content.

### macOS

- Main-window categories retain their meaning. Add a deliberate panel destination
  and native compact previews without changing the definition of existing counts.
- A separate desktop companion can host user-pinned panels. The interrupt island
  remains reserved for attention; routine chart updates do not open it.
- Drag near the left or right usable screen edge to snap. A visible control or
  keyboard command expands/collapses the companion; hover is optional, never required.
- Persist edge, display identity, and size per device. Display removal relocates
  the panel into a visible screen area. Respect the Dock, menu bar, and safe areas.
- Opening on a data update must not steal focus. Text entry explicitly activates
  the window. Multi-display, Spaces, full-screen apps, and Stage Manager behavior
  are validation cases, not assumed guarantees.
- Provide hide, unpin, resize, and ordinary-window actions. The user controls
  persistence and placement; an agent can only suggest a panel is worth pinning.

### Native design boundary

The existing native contract requires system controls where available. Adopting
React in WKWebView for full panels would be a **scoped proposed exception** for
generated content, including form controls; it is not already covered by the
native contract. Navigation, attribution, pinning, settings, errors, and critical
submission review remain native.

Phase 0 must compare that approach with a shared SwiftUI renderer for the initial
catalog. Record the selected approach and any exact contract amendment before
production UI implementation. Do not silently replace native forms with web forms
or assume that official React Native support supplies a SwiftUI adapter.
The current official renderer list does not include SwiftUI.
[Renderer documentation](https://json-render.dev/docs/renderers)

### System Live Activities and notifications

Use a separate, small, typed summary: task title, stage, optional numeric progress,
one key metric, freshness, and a deep link. Full questionnaires open the app.
Only explicitly user-enabled active tasks start system activities; starting a
panel must not create one automatically.

ActivityKit uses SwiftUI/WidgetKit and imposes payload and lifecycle limits.
Do not design an indefinite background dashboard or embed React there. Treat
APNs updates as system-managed delivery, not a real-time SLA. Confirm supported
surfaces against our deployment targets during implementation.
[ActivityKit](https://developer.apple.com/documentation/activitykit),
[Live Activity constraints](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

## 7. Questionnaire and decision experience

Supported initial inputs: text, multiline text, numeric input, single/multiple
choice, toggle, and bounded slider. Add date/time, multi-step navigation, comparison
selection, and batch review after the initial submit flow passes end-to-end tests.

- Declare stable field IDs and choice/item IDs; display labels are not identifiers.
- Show required fields and errors inline, plus a navigable error summary on submit.
- Reveal dependent questions from explicit conditions. Inactive fields are omitted
  from answers and do not remain hidden required blockers.
- Save draft changes locally. No keystroke stream is sent to the agent by default.
- Mark remote previews as previews; editing or previewing never counts as approval.
- Show the precise proposed operation and selected parameters before committing an
  authorization request. Intake answers authorize no unrelated task actions.
- Preserve submitted answers as read-only history. Corrections create a linked new
  request; accepted answers are never silently edited.
- Expiration closes a request without inventing an answer. Initial generated forms
  have no automatic default submission, even when simple existing options do.

json-render supplies binding and validation primitives; our submit handler must
explicitly enforce validity, and the server must validate independently.
[Validation and submission behavior](https://json-render.dev/docs/validation)

## 8. Task and request lifecycle

Panel task state: `running`, `paused`, `completed`, `failed`, or `cancelled`.
Freshness (`live`, `stale`, `offline`) and `archivedAt` are separate attributes.
An unresolved blocking request derives a `needs_input` presentation; it does not
grant the renderer authority to change the task state.

Request state: `open` becomes exactly one of `submitted`, `expired`, `withdrawn`,
or `superseded`. Publication edits create a new request revision and supersede
the open predecessor atomically. Terminal requests are immutable.

Completion requires pending requests to be resolved or explicitly withdrawn in
the same lifecycle operation. The producer saves a final snapshot before the
panel becomes terminal. Terminal panels do not accept further producer data.
Archive changes visibility; it does not assert successful task completion.

## 9. Initial scope and deliberate exclusions

Initial scope includes an agent catalog, panel publication, live state relay,
recoverable snapshots, compact native previews, one full renderer, simple forms,
durable submissions, and shared history/attention integration on both clients.

Later milestones cover desktop docking, complex forms, system summaries, and
optional P2P. A public component marketplace, arbitrary TSX/HTML execution,
arbitrary npm installation, simultaneous collaborative editing, automatic form
approval, full telemetry retention, and remote desktop control are outside this plan.

Discord, Telegram, and hardware surfaces receive a readable request summary and
a link to a capable client. This is an explicit channel representation, not an
attempt to translate complex forms into legacy string options.

## 10. Design completion versus feature completion

This planning package is complete when boundaries, protocols, ownership, failure
behavior, dependencies, and acceptance gates are reviewable. Feature completion
requires the later work packages and evidence in the [delivery plan](live-panels/rollout.md).
No production implementation, tests, migrations, or release are performed as part
of this documentation task.

## 11. Multiple producers on one surface — the tile wall

Decided 2026-09-07. Several agents publish to the same recipient at once, and the macOS
Panels destination presents them together as a wall of independently living tiles rather
than one panel at a time. The reference feel is a Live Tile wall: each tile is driven by
its own source, updates on its own schedule, and animates in place.

The transport already supports this. A PanelRoom is keyed by recipient, subscriptions
name individual panels, and fan-out to several device sockets was proven in the Phase 0
relay spike. What changes is presentation, plus the rules below, which are not decoration.

**The wall lays itself out, and the layout is stable.** The boss does not place tiles.
The arrangement is computed from the set of panels, their content-derived sizes, the
available width, and any user pins — and from nothing else. It is emphatically **not** a
function of the data, the values, or which producer pushed most recently.

That distinction is the whole rule. The obvious implementation sorts by recent activity
and repacks on every update, which makes the wall churn continuously and puts a tile
somewhere different each time the boss looks away. A producer pushing new numbers must
never move anything. Only three things may change the arrangement: a panel appearing, a
panel leaving, or the window changing width.

New panels append rather than insert, so existing tiles keep their slots. When packing
mixed sizes, prefer a deterministic fill: the same set of panels at the same width must
always produce the same arrangement, and a later tile changing size must not pull an
earlier tile into a gap it previously left open. Reflow on resize is expected and fine;
reflow on data is a defect.

**Every tile names its producer.** With one panel the owner is implicit. With several,
attribution is a correctness property: a metric whose agent is unidentifiable is a
misleading number, not a compact one.

**Freshness is per tile.** Producers update at different rates and some stop. A tile
nobody has pushed to in twenty minutes must look stale on its own, using the existing
live/stale/offline distinction. A Live Tile can afford to look identical when idle
because a local app backs it; a tile backed by a possibly disconnected agent cannot.

Two existing rules extend unchanged. Tile updates never open the interrupt island, which
stays reserved for things needing a decision. Staggered animation respects the reduced
motion setting, and the wall must remain legible with all animation disabled.

Tile size follows content rather than importance: a single scalar earns a small tile, a
series earns a wide one. Importance belongs to attention, which is a separate surface.
