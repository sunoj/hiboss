# HiBoss product roadmap

Updated: 2026-10-04. This is the current product index. The
[version history](../.aid/knowledge/roadmap-history.md) records earlier changes;
individual design contracts define behavior in detail.

Statuses describe source capability, not installation or production rollout.
Runtime behavior is verified only where the linked evidence says so. The CLI
package currently declares version **1.11.0**, which adds `hiboss box`; the next UX slice has no release
number assigned yet.

## Current capabilities

| Surface | Implemented behavior | Evidence / contract |
| --- | --- | --- |
| Agent CLI | Messages, blocking choices, progress posts, panels, durable questionnaires, project identities and key lifecycle; per-runtime profiles, invite-based `hiboss setup` with resumable approval, per-profile session state and dispatched mode | [CLI reference](../.aid/knowledge/cli-reference.md), [questionnaires](live-panels/questionnaires.md), [projects](projects-rollout.md), [multi-profile onboarding](multi-profile-onboarding.md) |
| Mac | Dashboard, attention categories, history, shared reply drafts, Island/window presentation, panels, pairing (issue and redeem codes), device-request approval and passive message notifications | [Mac setup](../macos/README.md), [overview](macos-information-redesign.md), [notifications](macos-message-notifications.md) |
| iOS | Home attention merges decisions and questionnaires; conversation-oriented session transcripts, message browsing, native localization and widget choices; timeout auto-selections are labelled as such, one reply admission point per decision, pairing and device-request approval | [attention model](native-client-attention-model.md), `ios/App/Home/HomeView.swift`, `ios/App/Shell/RootTabView.swift`, [2026-10 UX investigation](investigation-ios-ux-2026-10.md) |
| Panel lifecycle | Independent task/placement states, leases, expiry, durable submissions and live wall discovery | [implementation](live-panels/implementation.md) |
| Delivery model | Boss clients, projects, providers/destinations and credential identities | [entity model](entity-model-redesign.md), [destination modes](destinations-rollout.md) |

The old iOS Home dashboard contract describes a retired UI surface. The current
shell, rather than that document or the July iOS audit, defines navigation.
The destinations implementation supports `off`, `shadow` and `on`; this roadmap
does not infer the active server mode from source or historical deployment notes.

## UX priorities

The [Mac UX audit](macos-ux-audit.md) records current failures and visual evidence.
The [CLI UX reference](cli-ux.md) describes the implemented command-discovery and
local-tool slice. Neither document claims a published release.

| ID | Priority | Scope | Observable completion criterion |
| --- | --- | --- | --- |
| MAC-01 | P0 | Main-window recovery | "Open HiBoss" opens the main scene after its window closes, including Island mode without a Dock icon. |
| MAC-02 | P0 | Honest reply outcomes | An already-resolved reply does not clear the draft or claim local success; the winning resolution is visible. |
| MAC-03 | P1 | Unified pending-input meaning | Dashboard does not say "Nothing needs you" while a published questionnaire requires answers; Mac attention includes both task kinds. |
| MAC-04 | P1 | Connection and stale-data visibility | A failed or disconnected fetch cannot look like a successfully loaded empty inbox; recovery remains reachable with cached content. |
| MAC-05 | P1 | Decision history | Unanswered expiry differs from a recorded default choice; resolved detail identifies the winning answer and source. |
| MAC-06 | P1 | Island state consistency | Frame, content, Skip and reply feedback belong to the same presented question. |
| MAC-07 | P1 | Reply and questionnaire task completion | Inputs, blocking errors and submit remain usable at 480 × 400; drafts survive errors. |
| MAC-08 | P1 | Navigation and keyboard access | Dashboard, attention, history and panels have discoverable entry/return actions; primary tasks work with keyboard navigation. |
| MAC-09 | P2 | Native readability | Long questions/options, light/dark appearance and localized text preserve hierarchy and visible actions; actual native renders support the result. |
| CLI-01 | P1 | Command discovery | Root help groups commands by intent and includes usable messaging, panel and questionnaire examples; help works before setup. |
| CLI-02 | P1 | Local/offline tools | Built-in guidance and local validation work without server configuration; diagnostics use stderr and machine-readable output uses stdout. |
| CLI-03 | P1 | Configuration recovery | First-use and malformed-configuration failures explain the next safe command and retain established exit-code behavior. |
| CLI-04 | P2 | Task and delivery feedback | Long waits and failed delivery distinguish accepted, replied, timed out and unacknowledged outcomes, with a clear read/retry command. |

P0 covers false decision confidence or inaccessible primary surfaces. P1 covers
core task comprehension or completion; P2 covers consistency and readability.
The audit records the October 2 baseline for MAC-01 through MAC-06 at the source,
synthetic-state or render levels. Its source-fix table describes subsequent
changes; live interaction gaps remain explicit there.
MAC-07 through MAC-09 include behaviors still needing interactive verification.

| Scope | Current source status | Verification boundary |
| --- | --- | --- |
| MAC-01 | The status menu opens the main scene by ID; early requests survive opener installation. | Navigation tests and four synthetic native close/reopen cycles in accessory mode; actual menu click and closed-at-launch case remain unverified. |
| MAC-02 | Only accepted replies clear drafts. Conflicts refresh authoritative history and preserve message-specific drafts, including Island presentation changes. | Scripted accepted/conflict/failure and stream-resolution tests; native conflict/failure renders. |
| MAC-04 | Settings displays the actual connection state and failure detail. | Stream handshake truth and content-level stale-data banners remain unresolved. |
| MAC-06 | Island draft, submitting and failure feedback use the presented message ID. | Frame sizing and Skip still follow the live message. |
| MAC-07 | Notification-opened decisions use the shared reply flow and the loaded message's canonical ID. | Two callback-composition tests; actual notification click, button interaction and minimum-size task completion remain unverified. |
| MAC-09 | Devices uses an available symbol; the sidebar Settings footer has a native material background. | Synthetic light/dark renders; keyboard, VoiceOver and live selection rendering remain unverified. |
| CLI-04 | `status` is read-only, supports JSON, retains reply assurance and labels recorded automatic defaults separately from other replies. | Ten executable loopback tests; live delivery and long-wait/retry feedback remain outside this slice. |

CLI-01 through CLI-03 have an implemented first slice: six command groups,
messaging/panel/questionnaire examples, offline guide/validation, recovery without
config-value echoes, and preserved load-error/required-value exit statuses.
Verification: 273 CLI tests passed on a Linux build host, including 21 executable
UX tests. The combined Mac changes passed 203 tests; HibossKit passed 152 XCTest
tests and one Swift Testing test. Mac baseline: 175 tests passed; its native harness passed
9 additional render/state tests and captured 33 images. These results do not
verify live delivery, native keyboard/VoiceOver use or the installed binaries.
Configuration-load and provenance failures have typed exit handling. Other CLI
errors still use text matching, so server response bodies and request URLs can
affect their exit status; the CLI reference describes the current classifier.

## Dependent product work

| Scope | Current boundary | Required behavior |
| --- | --- | --- |
| Mac unified attention | Mac message decisions and panel requests have separate discovery surfaces; iOS Home already merges both. | One ranked Mac attention entry point without duplicate tasks; resolved/expired requests leave actionable lists. |
| Background panel discovery | Live wall signals reconcile foreground state. | Background discovery has explicit delivery/freshness semantics and does not promise reception while the app is offline. |
| Notification settings | Native passive notifications and destination delivery have distinct policies. | Settings explain actual enforcement and delivery state; destination changes reflect the effective delivery mode. |
| Delivery cutover | `shadow` observations never schedule sends; legacy queues are separate. | Mode changes and legacy removal require delivery parity evidence, queue reconciliation and native settings that reflect enforcement. |
| Panel projections | Panels do not currently render in Dynamic Island. | Bounded ActivityKit summaries, update/end behavior and device interaction evidence. |
| Execution forms | Questionnaire acceptance captures answers. | Execution authorization has its own explicit contract; timeout defaults and withdrawals never count as approval. |
| Identity cleanup | Legacy credential and delivery paths remain in the documented transition. | Remove old paths only when active consumers and persisted records no longer depend on them. |

See [remaining panel scope](live-panels/implementation.md#remaining-product-scope),
[questionnaire boundaries](live-panels/questionnaires.md#verification-and-remaining-scope)
and [destination behavior](destinations-rollout.md). These dependencies do not
block local command-discovery or native navigation improvements.

## Verification boundaries

- Mac evidence must distinguish source tracing, native rendering and interactive
  behavior. A passing build cannot establish contrast, focus or host visibility.
- CLI evidence uses isolated configuration and executable-level checks, including
  stdout/stderr and exit status. Tests run against controlled endpoints.
- Server deployment, installed-client versions, real delivery and physical-device
  behavior require their own receipts; source completion alone proves none of them.
