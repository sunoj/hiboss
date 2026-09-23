# HiBoss Roadmap and Takeover Baseline

Updated: 2026-09-23. Source baseline: `38c8570` (2026-09-12), CLI `1.10.0`, migrations through `0045_agent_keys.sql`.

This is the planning entry point. Historical designs and rollout records retain their original context. Implementation has been authorized; milestone completion still requires the evidence described below. All new documentation, code, and commit messages must be in English. Chinese is used only in conversation.

## 1. Product direction

HiBoss is a self-hosted Agent-to-Boss communication and decision tool. It helps people discover work requiring intervention, respond reliably, and observe progress. A Boss can also be another Agent.

| Workstream | User question | Existing surfaces |
| --- | --- | --- |
| Decisions and replies | What needs my attention? Did my answer take effect? | ask/options, Inbox, signed replies, durable questionnaires |
| Notification delivery | Who receives this, where, and without omissions or duplicates? | Destinations, external channels, APNs, SSE |
| Work visibility | What is happening in each project, and what was produced? | Projects, Sessions, Home, Progress, Live Panels |
| Agent integration | How do agents connect, address peers, isolate sessions, and confirm delivery? | Rust CLI, MCP, hooks/daemon, A2A |

Preserve the recorded boundaries: self-hosting and a single deployment's Boss set; no SaaS billing, organization tenancy, built-in email, or central push relay. External orchestrators own execution and scheduling. The aid safety engine belongs in the ai-dispatch repository.

References: [architecture decisions](../.aid/knowledge/architecture-decisions.md), [entity model](entity-model-redesign.md), [native attention model](native-client-attention-model.md).

## 2. Evidence and current state

- **Implemented:** source, contracts, or tests exist in this checkout; this does not imply tests passed during takeover.
- **Historically deployed:** a dated document records deployment; current production configuration remains unverified.
- **Needs verification:** requires tests, operational inspection, or device observation.
- **Planned:** a design or proposal, not an available capability.

The entity-model document records phases 0–4 deployed on 2026-09-12, with destinations still in `shadow` and phase 2c outstanding. Some subordinate rollout documents retain earlier statements that their changes were not deployed. Reconcile these using timestamps and operational evidence.

Elapsed calendar time does not establish parity. Require an observed window, coverage, explained differences, and disposition of queued work. Production Worker, D1, channels, and devices were not inspected during the initial inventory.

## 3. Architecture and module map

```text
Agent -- CLI / MCP / hooks -- HTTP / SSE -- Worker (Hono)
                                           | D1: identities, messages, projects, delivery, interactions
                                           | R2: attachments and update artifacts
                                           | Durable Objects / WebSocket: live panels and other streams
                                           | Discord / Telegram / APNs
Boss -- Web / iOS / macOS -- HTTP / SSE / WebSocket
```

| Module | Responsibility | Takeover focus |
| --- | --- | --- |
| `server/` | Worker, auth, routing, D1, delivery, panels | Migration ordering, access boundaries, receipts, retries |
| `cli/` | Rust CLI 1.10.0: messages, sessions, panels, requests, keys | Installed-version compatibility, default-answer provenance, session isolation |
| `mcp/` | Bun MCP channel and SSE bridge | Reconnection, signature verification, session cleanup, tool coverage |
| `web/` | Svelte 5 / SvelteKit console | Devices, Notifications, Projects, Agent Keys, legacy Channels route |
| `HibossKit/` | Shared native models, APIs, streams, panels, questionnaires | Consistent contracts and state across clients |
| `ios/` | Home, Inbox, Sessions, Progress, panels, APNs, decision Live Activity | Physical-device delivery, background recovery, questionnaire discovery |
| `macos/` | Native workspace, Island, notifications, pairing, Sparkle | Destination settings, installation and update verification |
| `panel-runtime/` | TypeScript panel contracts, validation, catalog, fixtures | Schema and native-renderer consistency |
| `spikes/` | Renderer and bridge experiments | Preserve as design evidence, not production deliverables |
| `terminal/` | Dependency lock and sdkconfig in this checkout | No complete firmware implementation found; outside core delivery commitments |
| `.aid/`, `docs/` | Knowledge, orchestration history, contracts, validation | Separate historical status from current facts |

## 4. Capability inventory

| Capability | Current evidence | Remaining focus / reference |
| --- | --- | --- |
| Messages, attachments, options, replies, forwarding, reactions | Implemented with release history | Receipt consumers in destination on mode; `server/src/routes/` |
| Multiple Bosses, access control, signing, provenance | Implemented | Revocation, isolation, downgrade regression coverage; `server/src/message-security/` |
| Boss clients, pairing, revocation | Phases 1a/1b historically deployed | New-client destination provisioning and device verification |
| Boss-owned destinations | Phases 2a/2b; historically shadow | Phase 2c is the near-term critical path; [rollout](destinations-rollout.md) |
| Delivery deduplication, quiet hours, retries | Destination and legacy queue implementations exist | Coverage, terminal states, replay, rollback; `server/src/delivery/`, `scheduled.ts` |
| Projects, aliases, rename/merge | Phases 3a/3b historically deployed | Retained text columns and local session slots; [rollout](projects-rollout.md) |
| Agent identity/credential split and rotation | Phase 4 historically deployed | Legacy hash/fallback and admin markers; [rollout](agent-keys-rollout.md) |
| Session stream, A2A addressing and acknowledgment | Implemented | Same-directory multi-agent isolation, reconnect catch-up, ACK |
| Home and Progress feed | Implemented using canonical projects | Attribution, media, cross-client consistency |
| Live Panels lifecycle v2 | Implemented with deployment records | Expiry, renewal, recovery, terminal state, wall consistency; [status](live-panels/implementation.md) |
| Durable questionnaires and typed answers | Implemented; deployment recorded 2026-09-11 | Shared attention, background discovery, device/offline verification; [contract](live-panels/questionnaires.md) |
| Message-decision Live Activity | Implemented | Validate separately from panel projection |
| Panel Dynamic Island projection | Feasibility design only | Later enhancement; [design](live-panels/dynamic-island.md) |
| Release and self-hosting | Module scripts and instructions exist | Compatibility matrix and reproducible acceptance; no tracked `.github/` workflows found |

## 5. Risks and confirmed gaps

| ID | Priority | Gap | Evidence and response |
| --- | --- | --- | --- |
| R01 | P0 | Current deployment is not reconciled with historical records | Inventory Worker, migrations, mode, installed clients, observation window |
| R02 | P0 | Notification edits do not affect delivery in shadow mode | Explicit rollout behavior; preserve mode messaging and legacy controls |
| R03 | P0 | Cutover can strand queues, routes, or receipt consumers | Inventory pending/processing/failed work; on mode does not automatically create threads |
| R04 | P0 | Automatic defaults can be mistaken for human approval | Local SAFE-01 now exposes outcomes and suppresses default actions; regression checks passed; review and client rollout remain |
| R05 | P1 | Deleting a Boss referenced by panels lacks business-level handling | Direct DELETE in `server/src/routes/bosses.ts`; implement reassignment or explanatory 409 |
| R06 | P1 | Local session slots are keyed by project-directory hash | `cli/src/session.rs`; reproduce multi-agent collisions and unify namespaces |
| R07 | P1 | Native destination provisioning, filtering, and receipts are incomplete | Deferred in destination rollout; define registration, revocation, settings lifecycle |
| R08 | P1 | Questionnaires lack shared attention ranking and background discovery | Explicit remaining scope in questionnaire contract |
| R09 | P1 | Takeover validation is not reproducible in the current environment | Isolated toolchains now validate CLI, MCP unit tests, schema, and Web tests/typecheck/build; server/E2E and remaining module baselines are still outstanding |
| R10 | P2 | Historical audits and current backlog are mixed | Classify findings as resolved, reproduced, or unverified before scheduling |

P0 identifies a delivery gate requiring resolution or evidence, not a claim of an observed production incident.

## 6. Milestones

Use acceptance gates rather than unverified calendar estimates. M0 → M1 → M3 is the migration sequence. M2 can proceed once contracts are clear. M4 continues after baseline validation is established.

### M0: Establish a verifiable takeover baseline

- [ ] Inventory Worker version, D1 migrations, destination mode, CLI/native/Web versions, and rollback artifacts.
- [ ] Restore Python 3.10+ validation and establish module test/build baselines in the prescribed environments.
- [ ] Collect shadow coverage, errors, difference categories, routes, and legacy backlog; restart observation if evidence is incomplete.
- [ ] Review default-answer and action behavior; expose machine-readable answer provenance without presenting a default as human choice.
- [ ] Reconcile historical audits with current implementations and regression tests.

Acceptance: a timestamped baseline with versions and evidence locations; reproducible failures and explicit untested scope. Existing tests or screenshots do not substitute for current results.

### M1: Complete destination delivery cutover

- [ ] Provide route configuration needed for cutover; decide explicit provisioning versus automatic thread/topic creation per use case.
- [ ] Migrate receipt consumers for replies, forwarding, edits, reactions, and option withdrawal where they still use legacy fields.
- [ ] Complete native destination provisioning/revocation and define notification configuration versus native_live capabilities.
- [ ] Complete at least one week of effective shadow comparison with understood coverage and no unexplained omissions or wrong targets.
- [ ] Drain or explicitly disposition the legacy queue, enable on mode while retaining the legacy model, and verify representative real channels.
- [ ] Record rollback behavior: off restores legacy delivery for new sends; on retries pause; inspect stale work before resumption; never replay shadow rows.

Acceptance: evidence for applicable Discord, Telegram, APNs, and foreground-native scenarios, including shared-target deduplication, urgent delivery, quiet hours, retries, revocation, and inbound routing. Provider acceptance, device display, and human reading remain distinct states.

### M2: Unify the attention and response workflow

- [ ] Add durable questionnaires to shared attention/inbox with consistent ranking, blocking state, deadlines, and deep links.
- [ ] Implement background APNs discovery with privacy, preferences, deduplication, and expiry semantics.
- [ ] Align native Notifications pages with server destinations; local-only controls must not imply global changes.
- [ ] Verify request → discovery → one accepted submission → Agent consumption → acknowledgment → cross-client convergence.
- [ ] Verify physical-device background/offline recovery, other-client resolution, Secure Enclave flows, and accessibility.

Acceptance: blocking requests are discoverable without repeatedly browsing panels; answer revision, origin, and consumption are traceable; disconnection does not appear as all-clear; duplicate submissions do not cause duplicate execution.

Ordinary questionnaire answers remain distinct from execution authorization. Dedicated authorization forms require a separate contract.

### M3: Retire compatibility paths and complete identity consistency

- [ ] Fix referenced-Boss deletion and local multi-agent session namespaces; these can start earlier.
- [ ] Measure legacy-client and fallback usage; establish minimum supported versions and rollback periods.
- [ ] After on mode is stable and rollback windows close, remove legacy channel configs, routing rules, delivery queues, and external-identity columns in separate migrations.
- [ ] Remove project text columns, legacy session label/thread writes, and unused session_info only after consumer verification.
- [ ] Retire legacy key_hash, auth fallback, and Agent admin-role markers after old Workers are gone; preserve independent Boss roles.
- [ ] Review remaining client binding and interaction client-provenance work and schedule according to actual dependencies.

Acceptance: each migration has backup/recovery instructions, counts and FK checks, fresh/upgrade schema parity, and compatibility evidence. Do not combine cutover and destructive cleanup into one irreversible step.

### M4: Make validation and releases reproducible

- [ ] Define validation entry points and compatibility matrices for server, CLI, Web, MCP, panel-runtime, HibossKit, and native clients.
- [ ] Gate merges on schema parity, access isolation, option convergence, delivery, and panel lifecycle coverage.
- [ ] Verify self-hosting from an empty environment to the first successful message; update stale setup instructions.
- [ ] Verify macOS signing and Sparkle update/recovery, plus iOS installation, pairing, and physical-device APNs.
- [ ] Establish diagnostics and retention policies for exhausted retries, shadow errors, stream reconnects, and panel recovery.

Acceptance: another maintainer can reproduce setup and validation; release records identify versions, migrations, test/device evidence, and rollback steps.

### M5: Extend the stable core

- Panel Live Activity / Dynamic Island: reuse the extension with bounded summaries and APNs update/end support rather than a full panel renderer.
- Multi-step forms, Agent callbacks, and execution authorization: specify idempotency, identity, revocation, and replay before implementation.
- Improve project navigation across sessions, progress, panels, and results based on observed usage.
- Hardware terminal: recover buildable firmware and define the use case before committing core-project capacity.

## 7. Initial work queue

| Order / ID | Task | Dependency | Completion evidence |
| --- | --- | --- | --- |
| 1 / BASE-01 | Inventory deployed and installed versions | Operational read access | Versions, mode, migrations, timestamped evidence |
| 2 / QA-01 | Restore validation environment and record baseline | Toolchains and prescribed test environment | Actual results and explicit untested scope |
| 3 / SAFE-01 | Review/fix default-answer provenance and action output | CLI/MCP/server contracts | Human reply, automatic default, and timeout distinguishable; regression coverage |
| 4 / DEL-01 | Produce shadow report and phase-2c gap inventory | BASE-01 | Coverage, differences, queues, routes, receipt consumers |
| 5 / ID-01 | Implement referenced-Boss reassignment or 409 | Deletion contract | Clear referenced-object behavior and unchanged unreferenced deletion |
| 6 / SES-01 | Isolate agents sharing a working directory | Reproduction and compatibility plan | Independent session, daemon, and marker state |
| 7 / DEL-02 | Implement cutover prerequisites and prepare rollout | DEL-01, QA-01 | Tests, configuration, queue disposition, rollback package |
| 8 / UX-01 | Specify shared questionnaire attention | Existing attention/questionnaire contracts | Reviewable cross-client state, ranking, deep-link, expiry rules |

Ownership follows module maintainers until people are assigned. Estimate dates after BASE-01, QA-01, and DEL-01. Reliable delivery and trustworthy answers precede presentation enhancements.

## 8. Historical corrections and validation record

- The v1.6 history's unmerged-retry note is stale: both legacy queue retry logic and destination retries exist. Runtime behavior still needs verification.
- The 2026-07-24 iOS audit's swallowed-409 issue has an explicit `ReplyResult.alreadyResolved` path now; Inbox also handles loading errors and expiration. Do not reopen these findings without reproduction.
- Current broadcast handling returns failure when peer sends fail; the A2A incident report describes historical behavior.
- Migration 0044 retired progress_teams. Read older feed contracts alongside the projects rollout.
- README and historical release notes do not describe the entire current product. Use the evidence categories above for future status changes.

| Check | Initial result |
| --- | --- |
| Git status and history | Clean at takeover; latest commit `38c8570` |
| Modules, manifests, migrations, key source paths | Static inspection complete; not a line-by-line security audit |
| `sh server/scripts/check-schema.sh` | Blocked: Python 3.9.6 fails on a runtime union type alias; script requires Python 3.10+ |
| Server/E2E, CLI, Web/MCP/Swift suites | Not run during inventory; full server/E2E documentation specifies an authorized grok checkout |
| Production parity, D1, channels, devices, releases | Not inspected; deployment claims are historical records |

Track execution evidence in [the takeover work log](takeover-work-log.md). Update task status and remaining scope when work lands. Mark a delivery milestone complete only after implementation, required verification, and applicable rollout are complete.

Latest execution: the 2026-09-23 work log records review of all six open PRs (#9–#14), whose module trees already landed on main, and a passing Web baseline (135 tests, zero typecheck diagnostics, successful build). After authenticated re-verification, all six superseded PRs were closed without merging or deleting branches; no open PRs remain.
