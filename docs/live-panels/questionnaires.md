# Durable panel questionnaires

Migration `0038_interaction_requests.sql` and the updated production Worker were
deployed on 2026-09-11; see the [rollout record](rollout-2026-09-11.md) for CLI and
native client status. This document describes the implemented intake slice of the broader
[interaction protocol](protocol.md#6-interaction-publication-and-revision).

## Agent workflow

Attach an intake to an existing panel and retain the returned request ID:

```bash
hiboss request publish <panel-id> panel-runtime/fixtures/questionnaire-intake.json \
  --idempotency-key research-intake-run-1
hiboss request list <panel-id>
hiboss request show <request-id>
hiboss request wait <request-id> --timeout 1800
```

`wait` prints the structured accepted submission, including its ID, exact revision,
typed answers, provenance, acceptance time, and delivery state. A timeout prints
`state: "open", timedOut: true`; it never selects defaults. An expired or withdrawn
request returns that state with no fabricated answer. A separate acknowledgement
confirms receipt, not execution:

```bash
hiboss request ack <request-id> <submission-id>
hiboss request replace <request-id> revised.json --expected-revision 1
hiboss request show <request-id> --revision 1
hiboss request withdraw <request-id> --expected-revision 2 --reason "No longer needed"
hiboss panel complete <panel-id> --withdraw-requests "Remaining questions no longer apply"
```

Replace and withdraw act only on an open head with the expected revision. Replacing
an accepted questionnaire is forbidden. Publish a new request for corrections.
Reusing a publication key returns the original request ID; different content with
that key is a conflict. Reusing a submission ID requires identical semantic content.

## Publication push contract

A fresh blocking publication schedules one best-effort APNs send per device of the
panel's `target_boss_id`. Only an INSERT reporting `changes === 1` is fresh. The
route schedules delivery with `executionCtx.waitUntil`; push failures cannot fail
publication. Idempotent retries (including racing inserts), replacements,
withdrawals, and `blocking: false` never push. Missing APNs configuration is silent.
Invalid tokens and their APNs destinations are pruned through the shared device path.

Both `aps.category` and top-level `category` are `HIBOSS_REQUEST`. The alert title
is `<agentName> needs input`, subtitle is the panel title (omitted if unknown),
and body is the questionnaire title, or `Needs input` in private-push mode.
`aps.thread-id` is the target boss ID. Top-level fields are `panelId`, `requestId`,
`agentName`, and the questionnaire's `priority`; there is no `messageId`.
Clients should open the panel detail for this category, never the inbox.

Questionnaires reuse the message decision tier defaults: audible active delivery
at APNs priority 10, or time-sensitive for critical priority. `decision_alerts: false`
uses status tier defaults. Per-priority `push` preferences override `deliver`,
`sound`, and `level`, including `deliver: false`; sound and level determine APNs
priority. Existing message push behavior is unchanged.

As with existing direct boss-device pushes, `DESTINATIONS_MODE=on` suppresses this
path to avoid duplicate delivery. Off and shadow modes allow it. The destination
dispatcher currently handles messages only; questionnaire delivery in on mode is
not implemented by this change. Publication retries do not retry failed pushes.

## Definition and answer contract

The publication contains `kind: "intake"`, title, blocking flag, priority, catalog
identity, formSpec, answerSchema, defaults, immutable context, and optional expiresAt.
The server supports the shared bounded catalog and answer-schema subset. It rejects
unknown publication keys, undeclared bindings, mutable `/task` bindings, malformed
schemas, and invalid defaults. Defaults may omit required fields; submitted answers
must satisfy the complete schema. Document size is bounded to 64 KiB and answers to
16 KiB. The example fixture covers text, multiline text, multiple choices and a slider.

Inputs require `$bindState` paths under `/form/`; read-only evidence uses `$state`
under `/context`. Writable context bindings and item bindings are rejected. Answers are the
form object without a wrapper. Option IDs remain strings, including numeric-looking
IDs. Validation errors keep the request open and preserve the client draft.

Questionnaire expiry and panel visibility expiry are independent. A paused task
accepts answers. An expired questionnaire accepts none. Terminal task commands
reject unexpired open requests by default; explicit withdrawal closes only requests
still open in the same D1 transaction and requires a reason. Accepted answers survive.
`needsInput` is derived from unexpired open blocking requests in the list response.

## Persistence and identity

Migration 0038 adds request heads, immutable definition revisions, immutable accepted
answers, and delivery acknowledgements. A submission batch conditionally claims the
head, inserts the answer and provenance, adds a session event, and creates the delivery
record. Failure in any statement rolls back every statement. Answer submission,
revision replacement, withdrawal and task termination compete through D1 predicates.
Reads and mutations enforce the panel's target boss and current agent access.

Only manager/admin boss tokens submit. A token bound to a signing key must supply a
valid ES256 JWS with type `hiboss-interaction+jws`, purpose
`hiboss.interaction-submit`, exact request/revision/answers/boss/submission ID, and a
fresh `issuedAt`. Unsigned credentials record `not_configured` provenance. Signing
does not authorize any external execution; other request kinds are rejected.

Agent delivery is pull-based in this slice: an unacknowledged accepted submission
remains readable by `wait` and `show` until `ack` records receipt. Consumers deduplicate
using `submissionId`. There is no automatic callback dispatcher or execution claim.
`GET /api/interaction-requests/:id/submissions/:submissionId` recovers an ambiguous
submission. Acceptance retries return the original receipt, even after acknowledgement;
read the submission to obtain current delivery status.

## Native experience

iOS and macOS show a **Needs input** filter and per-card pending counts. Open optional
and blocking questionnaires remain discoverable when the panel's wall visibility
expires or the boss archives it. Closed tasks and expired questions leave this filter.
The filter uses `GET /api/interaction-requests`, which returns scoped summaries only,
with opaque cursor pagination (default 50, maximum 100). Definitions and accepted
answers are retrieved through the existing detail endpoints. Access is checked on
every page; the endpoint does not generate a push notification.

Panel detail pages list questionnaires and refresh every ten seconds. Loading,
retry, deadline, optional/blocking, saved draft, submitting, and receipt-check states
are explicit. Narrow layouts use a native menu for the wall filter. Select controls
show an unselected placeholder, multiselect uses native controls without a nested
scrolling list, and number fields preserve partially typed decimals.
Inputs use the shared native renderer. Drafts are scoped by server, boss, request ID
and revision in local storage. Changing task observations does not change the question.
When a revision changes, the old draft stays preserved and submission is disabled
until the user explicitly starts the new revision.

Submission IDs are saved before the network request. An ambiguous failure locks the
draft and offers a receipt check. If no receipt exists, the client refreshes the request
and requires another explicit submission. It never resends automatically on reconnect.
Recovery keeps the submission ID until the matching accepted answer has been read
back, including when the first post-submit read is stale. Accepted answers display
field labels, choice labels, acceptance time, and agent receipt status from server
records. English and Simplified Chinese strings are included in the native catalogs.
See the [native UI verification record](native-ui-2026-09-11.md) for build and installation evidence.

## Verification and remaining scope

Run E2E only on an authorized grok host, in an isolated directory:

```bash
npm ci
cp server/wrangler.toml.example server/wrangler.toml
npm run typecheck --workspace server
npm test --workspace server -- src/panels/requests/tests src/panels/lifecycle
cargo build --manifest-path cli/Cargo.toml --example request-driver
python3 cli/scripts/questionnaires/run-e2e.py
```

The Worker tests cover competing submissions, terminal races, version pinning,
expiry, permissions, signature tampering, retry recovery, and rollback on delivery
insertion failure. The CLI runner applies real migrations and tests five flows:
publication/retry, pending timeout, revision/readback, accepted answer/retry/ack,
and withdrawal. It writes logs under `output/questionnaire-e2e` on the execution host.

Shared attention/inbox ranking, automatic agent callbacks, execution
authorization forms, multi-step forms, and Live Activity projections remain outside
this slice. Native builds verify compilation; physical-device interaction, offline
recovery, accessibility, and Secure Enclave UI flows still need device verification.
