# Durable panel questionnaires

A questionnaire is an intake form that an agent attaches to one of its live panels and
the panel's target boss answers once. This document is the contract for the intake slice
of the broader [interaction protocol](protocol.md#6-interaction-publication-and-revision).
Server code lives in `server/src/panels/requests/`; migration `0038_interaction_requests.sql`
holds its tables.

## Who does what

| Action | Allowed caller |
| --- | --- |
| Publish, replace, withdraw, acknowledge | The agent that owns the panel |
| Read a panel's requests, a request or a submission | The owning agent, the panel's target boss while it can reach the agent, and any live `admin` boss |
| List pending requests (`GET /api/interaction-requests`) | The owning agent (its panels) or the target boss (panels that target it) |
| Submit an answer | The panel's target boss only, with role `admin` or `manager` |

A boss reaches an agent when it is a live `admin` or holds a grant to the agent. Every
write also requires the panel's target boss to be live and to reach the agent. A
`viewer` gets 403 on submit, and so does a boss that is not the panel's target,
including another `admin`; that 403 is returned before the request is claimed, so the
request stays open for the target. Agent tokens cannot submit.

## Agent workflow

Attach an intake to a running or paused panel and retain the returned request ID:

```bash
hiboss request publish <panel-id> panel-runtime/fixtures/questionnaire-intake.json \
  --idempotency-key research-intake-run-1
hiboss request list <panel-id>
hiboss request show <request-id>
hiboss request wait <request-id> --timeout 1800
```

`wait` prints the structured accepted submission, including its ID, exact revision,
typed answers, provenance, acceptance time and delivery state. A timeout prints
`state: "open", timedOut: true`; it never selects defaults. An expired or withdrawn
request returns that state with no answer. A separate acknowledgement confirms
receipt, not execution:

```bash
hiboss request ack <request-id> <submission-id>
hiboss request replace <request-id> revised.json --expected-revision 1
hiboss request show <request-id> --revision 1
hiboss request withdraw <request-id> --expected-revision 2 --reason "No longer needed"
hiboss panel complete <panel-id> --withdraw-requests "Remaining questions no longer apply"
```

Replace and withdraw act only on an open, unexpired head with the expected revision.
An accepted questionnaire cannot be replaced; publish a new request for corrections.
Reusing a publication key returns the original request ID; different content with
that key is a conflict. Reusing a submission ID requires the same boss and identical
semantic content, and returns the original receipt.

## Definition and answer contract

The publication contains `kind: "intake"`, title, blocking flag, priority, catalog
identity, formSpec, answerSchema, defaults, immutable context and optional expiresAt.
Other request kinds, including authorization requests, are rejected. The server
supports the shared bounded catalog and answer-schema subset. It rejects unknown
publication keys, undeclared bindings, mutable `/task` bindings, malformed schemas,
invalid defaults and an expiry in the past. Defaults may omit required fields;
submitted answers must satisfy the complete schema. A document is at most 64 KiB and
answers at most 16 KiB.

Inputs require `$bindState` paths under `/form/`; read-only evidence uses `$state`
under `/context`. Writable context bindings and item bindings are rejected. Answers are
the form object without a wrapper. Option IDs remain strings, including numeric-looking
IDs. A validation error keeps the request open.

## States and expiry

A request head is `open`, `accepted` or `withdrawn`. Expiry is derived: an open request
past its `expiresAt` reads as `expired` and accepts no answer, replacement or
withdrawal. Expiry never creates an answer.

Questionnaire expiry and panel visibility expiry are independent. A paused panel
accepts answers; a terminal panel accepts none. A terminal task command rejects
unexpired open requests by default (`openRequests: "reject"`). `openRequests:
"withdraw"` requires a reason and a terminal action, and withdraws only requests still
open in the same D1 batch. Accepted answers survive. `needsInput` in the panel's
request list is derived from unexpired open blocking requests.

## Persistence and identity

Migration 0038 adds request heads, immutable definition revisions, immutable accepted
answers and delivery acknowledgements. A submission batch conditionally claims the
open head, inserts the answer and provenance, adds a session event and creates the
delivery record. The claim rechecks, in the same statement, the revision, that the
request is open and unexpired, that the panel is running or paused, and that the
submitting boss is the live target boss with role `admin` or `manager` and an
unrevoked token. Failure in any statement rolls back every statement, so exactly one
answer wins. Submission, replacement, withdrawal and task termination compete through
these D1 predicates.

A token bound to a signing key must supply a valid ES256 JWS with type
`hiboss-interaction+jws`, purpose `hiboss.interaction-submit`, the exact request,
revision, answers, boss and submission ID, and an `issuedAt` within five minutes of
server time. A revoked signing key is refused, and a bound token cannot fall back to
an unsigned submission. Unsigned credentials record `not_configured` signature
provenance. Signing does not authorize any external execution.

Agent delivery is pull-based: an unacknowledged accepted submission remains readable
by `wait` and `show` until `ack` records receipt. Consumers deduplicate using
`submissionId`. The server has no callback dispatcher and no execution claim.
`GET /api/interaction-requests/:id/submissions/:submissionId` recovers an ambiguous
submission. Acceptance retries return the original receipt, even after acknowledgement;
read the submission to obtain current delivery status.

## Discovery

`GET /api/interaction-requests` returns summaries of open, unexpired requests on
running or paused panels, independent of the panel's wall visibility or the boss's
placement. It uses opaque cursor pagination (default 50, maximum 100) and checks access
on every page. Definitions and accepted answers come from the detail endpoints. The
endpoint never sends a push.

## Publication push

A fresh blocking publication schedules one best-effort push per device of the panel's
live target boss. Only an INSERT that created the request is fresh. The route schedules
delivery with `executionCtx.waitUntil`; a push failure cannot fail publication.
Idempotent retries (including racing inserts), replacements, withdrawals and
`blocking: false` never push, and a retry does not resend a failed push. A server with
no push transport sends nothing. Invalid tokens are pruned through the shared device
path.

Both `aps.category` and top-level `category` are `HIBOSS_REQUEST`. The alert title is
`<agentName> needs input`, the subtitle is the panel title (omitted if unknown), and the
body is the questionnaire title, or `Needs input` when the boss uses private push.
`aps.thread-id` is the target boss ID. Top-level fields are `panelId`, `requestId`,
`agentName` and the questionnaire's `priority`; there is no `messageId`. Clients open
the panel detail for this category, never the inbox.

Questionnaires use the message decision tier defaults: audible active delivery at APNs
priority 10, or time-sensitive for critical priority. `decision_alerts: false` uses
status tier defaults. Per-priority `push` preferences override `deliver`, `sound` and
`level`, including `deliver: false`; sound and level determine APNs priority.

With `DESTINATIONS_MODE=on` this direct device push is skipped, and the destination
dispatcher delivers messages only, so a questionnaire sends no push in that mode. Off
and shadow modes push.

## Native clients

iOS and macOS show a **Needs input** filter backed by the discovery endpoint, and
per-card pending counts. Panel detail lists the panel's questionnaires. Drafts are
stored locally per server, boss, request ID and revision. When a revision changes, the
old draft stays and submission is disabled until the user starts the new revision.

A client saves the submission ID before sending. After an ambiguous failure it locks
the draft and offers a receipt check; if no receipt exists it refreshes the request and
requires another explicit submission. It never resends automatically, and it keeps the
submission ID until the accepted answer has been read back.
