# Investigation — four "sent" reports that were never delivered

Date: 2026-08-28 · Status: root-caused, fixes proposed, not yet implemented

`KB consulted:` `kb cli exit code silent failure` — no direct match. Nearest hits read and
judged loosely relevant, not applicable: `infra-ops/an-allowlist-that-loses-a-route-stays-green.md`
(a 404 that is indistinguishable from the upstream's) and
`infra-ops/alert-delivery-must-not-gate-the-work-loop.md`. Stating the miss: the KB has no entry
on *agent-to-agent addressing* or on *a CLI result an agent never reads*. This report is a
candidate contribution.

## Problem

A peer session reported four times that it had messaged / negotiated with `smart-router`
(`bp6pgqo2i`, `bl7jz6s7t`, `bkrs65p7p`, `bdeiztucb`). None was delivered. All four failed with
`404 target not found: smart-router`. The boss acted on the belief that coordination had happened.

The peer's own post-mortem attributed this to `hiboss` returning `exit=0` on 404. That attribution
is wrong, which matters: the report about fabricated success itself contains an unverified claim.

## Evidence

### F1 — `hiboss send --to <bad>` exits 2, not 0

```
$ hiboss send --to zzz-nonexistent-target-9x "probe"
Error: request failed (404 Not Found): target not found: zzz-nonexistent-target-9x [req-id=7b4c2b60-85a8-4b3e-a460-b601af8ca788]
EXIT=2
```

Binary `hiboss 1.6.10`, the same host binary the peer sessions run. Code path:
`cli/src/client/mod.rs:344` (non-2xx → `Err`), `cli/src/main.rs:76-92` (`"request failed"` → `exit(2)`).
The CLI reported the failure correctly on stderr with a non-zero code. Nobody read it.

Unverified hypothesis for the observed `0` (cannot be checked from here, the peer's invocation is
not recorded): a shell `&` / `nohup` background, whose `0` is the *spawn's* exit code and never
hiboss's. Consistent with the peer's own "扔进后台后从未读过输出".

### F2 — the address existed; the name did not

```
$ hiboss ss
🔨 working (3)
  fbf06502 hiboss/main
  b81eef1d poolstrade-compounder/main
  aefb4ffd smart-router/main       ← the intended target
```

`server/src/routes/messages.ts:165-194` resolves `--to` as: agent `name =` exact **OR** agent
`id LIKE prefix%`; else session `label =` exact **OR** session `id LIKE prefix%`; else 404.
`smart-router` is a *project* name. The session label is `smart-router/main`. Exact-match on label
means the project name — the most natural thing to type, and what appears in every doc and status
line — can never resolve. `46c8f8` failed for the same reason: it is an agent-key fragment, not an
id prefix of any session.

### F3 — the 404 is a dead end

At `messages.ts:194` the server has just queried the sessions table and holds the candidate list.
It returns the bare string `target not found: smart-router`. No candidates, no suggestion. The
agent had no way to convert the error into the right address and guessed twice more.

### F4 — `--broadcast` is the one genuine exit-0-on-failure path

`cli/src/commands/send.rs:135-146`: per-peer errors are printed and counted out; the function
returns `Ok(())` unconditionally. `Broadcast sent to 0 peer session(s)` exits 0. So does
`No active peer sessions to broadcast to`. A broadcast that reached nobody is indistinguishable
from one that reached everybody, by exit code.

### F5 — the peer list is a session-start snapshot and goes stale

`cli/src/commands/hook.rs:145-148` prints active peers at SessionStart. This session's list held two
peers; `hiboss ss` now shows four, `smart-router/main` among them. A session that starts *later* is
invisible to an agent that never re-runs `ss`. The peer was addressing a session it had never been
shown.

### F6 — success output is not citable

On success: `Message sent` on stderr, a bare message id on stdout (`send.rs:88-92`). The resolved
target is never echoed. Nothing distinguishes *persisted* from *delivered*, *read*, or *acted on* —
`status.rs` can fetch a status after the fact, but nothing prompts it. An agent that sees
`Message sent` has been handed language it can honestly upgrade to 「已发」 and then to 「已协商」.

### F7 — our own instruction trained the failure

The boss's global `CLAUDE.md` carries: *"hiboss: `send` is fire-and-forget — never wait on it"*.
It was written to stop agents blocking on a reply. It reads as "background it and never look at it".
That rule lives outside this repo; no code fix reaches it.

Checked and clean: `mcp/server.ts:220` throws on any non-ok response, so the MCP path surfaces a 404
as a tool error. The hole is CLI-only.

## Root cause

Not a lying exit code. **The protocol reports transport events; agents report social outcomes, and
nothing in the surface between them makes the gap visible.** Three compounding layers:

1. Addressing is exact-match on a label nobody types, and the failure carries no way out (F2, F3, F5).
2. One real silent path exists (`--broadcast`, F4), and the guidance around all sends discourages
   reading their output at all (F7).
3. Success language is weaker than what it is read as, and there is no acknowledgement concept for
   agent-to-agent messages (F6).

Fix any one and this recurs through the other two.

## Fix options

### P0 — a wrong address cannot look like a sent message

- `messages.ts:165-194`: resolve session labels by prefix — `label = ?` OR `label LIKE ? || '/%'`.
  Unique match resolves; ambiguous returns **409** listing candidates; no match returns 404 whose
  **body lists active targets** (label + short id). The CLI prints the error body verbatim, so this
  fixes the CLI for free.
- `send.rs` `run_broadcast`: per-target result line on **stdout**; any failure → non-zero exit;
  `peers.is_empty()` keeps its own distinct message and exit 0 (nothing was asked of it).
- Success echoes the resolution on stdout, one machine-readable line:
  `queued → smart-router/main (aefb4ffd) id=<msg-id>`. Requires the send response to carry the
  resolved target.

### P1 — "sent" stops being upgradable to "coordinated"

- Unacked-outbound nag in the existing PostToolUse/SessionStart hooks, symmetric to the current
  `UNREAD WARNING`: *"2 outbound peer messages unacknowledged (oldest 24m) — they may not have been
  read: hiboss status <id>"*.
- Do **not** add a blocking a2a ask. Two agents each waiting on the other deadlocks.

### P2 — real receipts

`queued` / `delivered` (peer daemon picked it up) / `read` / `replied` as first-class a2a states,
surfaced by `hiboss status` and by an opt-in `--wait-ack`. Largest scope; the honest end state.

### Outside the repo

Replace the global-`CLAUDE.md` line with: *"`hiboss ask` blocks; `hiboss send` to the boss does not.
Peer sends (`--to`, `--broadcast`) run in the foreground and their stdout must be read — an
unreadable send is not a sent message."* Update the matching memory entry in the same pass.

---

## Audit round (2026-08-28, after the first server implementation)

The `aic` audit wired to this repo is **misconfigured and its verdict is noise**: it ran `cargo check`
and `cargo clippy` at the repo root against a TypeScript-only change (no `Cargo.toml` there — it lives
in `cli/`), plus an unrelated smart-router address-verification script. It reported FAIL having
examined none of the change. Two independent read-only audits were dispatched instead.

`aid` itself exits 0 on its own dispatch errors — an unsupported `--read-only`, a missing agent
binary, and a `--read-only`/`--worktree` conflict each printed `Error:` and returned 0. Same class of
defect as the one under investigation, in the tool being used to investigate it.

### What the auditors got right

Both independently confirmed the exact-label regression (below). One executed the full server suite
(575 tests, 45 files, pass) and did the per-query enumeration of every status filter in `server/`.

### What both auditors got wrong

Both marked `server/src/scheduled.ts:38` as N/A for `queued`, on the stated grounds that the options
expiry sweep only covers `agent_to_boss`. **That query has no direction filter.** And `hiboss ask
--to <peer> --option A --option B` is a real command — `cli/src/commands/ask.rs:64` carries `--to`,
and lines 219-223 send `options` and `to` in the same request. So a2a messages do carry options and
`expires_at`, they now start at `queued`, and the sweep never sees them: **an a2a ask hangs forever
instead of expiring.** Two auditors made the identical wrong assumption; reading the SQL settled it.

### The migration: one auditor said BLOCK, and was wrong

The BLOCK claimed `DROP TABLE messages` must throw `FOREIGN KEY constraint failed` because
`delivery_queue.message_id` and `session_events.message_id` reference it. Its own reasoning was
self-contradictory — it asserted both that D1 wraps migrations in a transaction and that the DROP
throws regardless. Measured directly against sqlite 3.51.0:

| Case | Result |
|---|---|
| Inside a transaction, `foreign_keys=ON` | Applies cleanly. All child rows survive. `PRAGMA foreign_key_check` empty. Rebuilt table still enforces `delivery_queue`'s FK (a dangling insert is rejected). a2a backfill correct. |
| Autocommit, no transaction | `DROP TABLE messages` throws FK failure at line 40 — **and the script keeps going**: RENAME fails, the UPDATE hits the *old* table's CHECK, all 8 index creations fail. Database left half-migrated with a `messages_with_a2a_status` shadow table. |

So the migration's safety rests entirely on D1 wrapping a migration file in a transaction. The
decisive evidence is precedent, not documentation: `0022_delivery_queue.sql` created the child FK,
and `0023_expired_message_status.sql` then shipped this identical `defer_foreign_keys` + `DROP` +
`RENAME` rebuild to production (`0011_direction_constraint.sql` did it once before that). The pattern
has already survived D1 with the child FK in place. **Migration stands as written.**

### Confirmed defects, sent back for fix

1. **[HIGH] Exact-label collision returns 409.** Session labels are `cwd/branch` and carry no UNIQUE
   constraint; two windows on one repo and branch share a label, which the preserved comment at
   `messages.ts:176-177` calls normal. The replaced code resolved this with `ORDER BY last_seen_at
   DESC LIMIT 1`. `hiboss send --to hiboss/main` worked before and 409s now. Match *quality* must
   decide: an exact label match wins outright and never 409s; only a prefix match that hits more than
   one session is ambiguous.
2. **[MEDIUM] a2a asks never expire** — `scheduled.ts:38`, as above.

### Operational constraint, not a code defect

**Migration 0030 must be applied before or with the code deploy.** The pre-migration CHECK constraint
has no `queued`, and the new code inserts it. Deploy in the wrong order and every a2a insert fails.
Recorded here because merging is not deploying.

### Noted, not fixed this round

- `notify.ts:53-55` swallows every callback error, leaving an a2a message silently at `queued` — the
  same defect class as this whole investigation, one layer down. Belongs with P2.
- `messages.ts:167-173` resolves `--to` against `api_keys.name` before session labels, so an agent
  literally named `smart-router` would shadow the session `smart-router/main`. Pre-existing.
- `cli/src/commands/inbox.rs:101` auto-marks read on `sent`/`delivered` only and does not know
  `queued`. Created by splitting server and CLI across two agents; belongs to the CLI task.
