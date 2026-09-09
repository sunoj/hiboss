# Card expiry rollout

Date: 2026-09-09, later the same day as the agent channel rollout. Every card now
carries a visibility window that only an explicit renewal extends.

## Deployed scope

| Component | Result |
| --- | --- |
| Production D1 | Migrations `0036_panel_expiry.sql` and `0037_panel_stored_expiry.sql` applied |
| Worker | `2a98ee22-c5be-49bc-bc84-12b9ecb38b15`, serving production |
| Local CLI | 1.9.0 |
| Remote CLI, both agent hosts | 1.9.0, guidance refreshed |

## The rule

A publication declares `ttlSeconds`, default 3600, range 60 to 604800, and the server
stores the resulting `expiresAt`. Observations do not touch it. Renewal is a separate
owner-only operation, version-checked and refused on a terminal panel, reached through
`hiboss panel renew <id> [--ttl <seconds>]`.

A lapsed running or paused card leaves the active wall. Its task state is never changed,
because inferring failure from silence would misclassify a healthy task during a network
partition. A pin keeps a card visible. Terminal cards keep their own retirement deadline.
A renewal brings a lapsed card back.

## A defect caught before it shipped

Migration 0037 originally dated each card's window from `created_at`. Every running panel
in production had been created a day or two earlier, so the window was already spent and
applying it unchanged would have hidden all of them at once — indistinguishable, from the
outside, from a deploy that deleted the wall. The migration now dates the window from the
moment it runs. Read back after applying: eight of eight rows held a future deadline.

## Verification in production

- Panels list and read normally after the deploy; the checkpoint reports `expiresAt`.
- An explicit renewal on a live card moved its deadline forward by the window.
- On a card published with a 60-second window, an accepted observation changed the task
  values and left the deadline untouched, which is the rule the whole change exists for.
- A renewal carrying a new window replaced it, and the check card then completed normally.

The wall's hiding rule is covered by unit tests over task state, placement, expiry and the
server clock. It was not observed on a device as part of this rollout.

## Recovery

The previous Worker version was `045ecab4-2ef4-4ba2-9ee9-f40d9a98f165`. Taken before the
migration: the panel rows as JSON, and a full database export. Both migrations only add
fields to existing lifecycle records; neither deletes panel data. CLI backups sit beside
each installed binary.
