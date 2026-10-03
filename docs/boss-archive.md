# Reversible boss archive

Migration `0047_boss_archive.sql` adds nullable `bosses.archived_at` with ALTER TABLE.
Archive changes only that field. Grants, clients, tokens, panels, messages, and audit
history remain. Restore clears it; existing non-revoked tokens work again.

| Production selection site | Classification and policy |
| --- | --- |
| `middleware/auth.ts`: `resolveBossAuth` | Live: reject archived token owners. |
| `panels/access.ts`: `resolvedBosses`, `bossCanAccessAgent`, `panelTargetAccessSql` | Live: filter archived admins and grantees; discovery and publication inherit this. |
| `notify.ts`: boss-agent fan-out and request push target | Live: exclude archived recipients and their devices. |
| `delivery/destinations.ts` | Live: exclude archived owners, including retry resolution. |
| `delivery/inbound.ts` | Live: exclude archived route owners. |
| `panels/lifecycle/repository.ts`: admin authorization | Live: exclude archived admins; access helper also checks the target. |
| `panels/requests/submissions.ts`: answer commit guard | Live: exclude archived target/token owners. |
| `routes/boss-inbox.ts`: agent-as-boss identity | Live: exclude archived linked bosses. |
| `routes/webhook-helpers.ts`: account and channel identity | Live: exclude archived identities. |
| `routes/webhook-helpers.ts`: total boss count | History/security inventory: retain all rows so archival cannot reopen anonymous bootstrap access. |
| `routes/pairing.ts`: code claim and boss lookup | Live: exclude archived owners before consuming a code or issuing a token. |
| `routes/boss-api.ts`: own profile and preferences | Live: authenticated self selection excludes archived rows. |
| `routes/bosses.ts`: list, detail, target lookup | History: retain all bosses; list/detail expose `archived_at`; target guard returns 409 on mutation. |
| `routes/bosses.ts`: newly inserted identity CTE | Live: the just-created boss is unarchived by default. |
| `routes/boss-external-accounts.ts`: identity conflict | History/integrity: retain identities and uniqueness reservations so restore cannot create conflicts. |
| `routes/boss-external-accounts.ts`: target lookup | History for GET; archived mutations return 409. |
| `routes/quiet-hours.ts` | Live: archived preferences never delay delivery. |
| `routes/message-option-threads.ts`: thread invitations | Live: invite only unarchived granted Discord bosses. |
| `devices/notify-push.ts`: join-request APNs prompt | Live: only unarchived admins' devices. |
| `routes/join-notify.ts`: Telegram/Discord join broadcast | Not boss-scoped: posts to every enabled agent channel destination, like ordinary agent messages. Archival does not remove anyone from an external chat; approve/reject callbacks still require a live admin. |
| `routes/boss-archive.ts`: target/state reads and admin count | History targets permit restore; last-admin count includes only live admins. |
| Panel/message detail name-only joins and stored history | History: retain archived names and records. |

`POST /api/bosses/:id/archive` and `/restore` require an admin boss token and a full
boss ID. Unknown targets return 404; repeated state transitions return 409.
Archive rejects self and the last live admin with 400. The last-admin constraint
also guards the UPDATE atomically. Successful changes append `boss.archive` or
`boss.restore` audit events. No delete or token revocation occurs in either path.

The existing update verb is PATCH. PATCH (including preferences), grant/revoke,
token rotation, and external-account mutations reject archived targets with 409
`boss is archived`. Self-service routes reject archived callers at auth with 401.
The existing DELETE boss endpoint is unchanged, as required.

CLI: `hiboss boss archive <id>`, `hiboss boss restore <id>`; list includes an
`Archived` date or `-`. Restoration deliberately reuses retained identity records.
No production migration or deployment is part of this change.
