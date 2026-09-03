# Code-signing migration: YX8SMYQJ6U -> JHH9GC8Y8C

Moving HiBoss macOS + iOS signing from the org team **YX8SMYQJ6U** (MEET SOFTWARE
COMPANY LIMITED) to Ming's personal developer account **apple@mings.work**
(team **JHH9GC8Y8C**). Goal: distribute both clients; App Store listing is out of
scope for now.

## Account facts (verified 2026-09-03)

| Item | Value |
|---|---|
| Apple ID | `apple@mings.work` |
| Team ID | `JHH9GC8Y8C` |
| ASC provider ID | `122223253` |
| ASC issuer ID | `8099100b-af06-423e-bc8d-10f5eec00ee9` |
| Program agreement | `active`, accepted 2026-08-29 (paid membership valid) |
| Outstanding | EU DSA trader status undeclared — blocks EU App Store listing only |

`asc` CLI auth is stored in the login keychain as profile `hiboss-signing`
(key `X4MPPK98FQ`, p8 at `~/.asc/keys/AuthKey_X4MPPK98FQ.p8`).

## Decisions

1. **iOS bundle ID changes to `ai.hiboss.app`** (widget: `ai.hiboss.app.widgets`).
   `ai.hiboss.ios` is held by YX8SMYQJ6U and bundle IDs are globally unique;
   Apple returns "An App ID with Identifier 'ai.hiboss.ios' is not available".
   Deleting it from the old team was rejected: re-signing already forces a fresh
   install (iOS refuses a same-bundle-ID app from a different team), so deletion
   buys nothing but irreversibility.
2. **macOS keeps `ai.hiboss.island`.** The macOS app ships no entitlements file
   and is not sandboxed, so Developer ID signing needs no App ID and no profile.
3. **iOS distribution: both Ad Hoc and TestFlight.**
4. **Developer ID certificate: `DEVELOPER_ID_APPLICATION_G2`.** The classic
   (G1) intermediate expires 2027-02-01 and caps leaf validity at that date; G2
   gets the full 5 years and macOS 14 (our deployment target) is far above its
   minimum.

## Provisioned so far

| Resource | ID | Notes |
|---|---|---|
| Bundle ID `ai.hiboss.app` | `MTB4739ZXM` | PUSH_NOTIFICATIONS enabled |
| Bundle ID `ai.hiboss.app.widgets` | `ZJ2VF4X5CK` | no capabilities needed |
| Device `Ming iPhone 15 Pro` | `FU62NVTMSH` | UDID `00008130-000A352624E1401C` |
| Cert `Apple Distribution: Ming Sun (JHH9GC8Y8C)` | `G2V2Q9Y929` | expires 2027-09-03, in login keychain |
| Cert `Apple Development: Created via API (X4MPPK98FQ)` | `NM8C338CX9` | expires 2027-09-03, in login keychain. The CN says "Created via API" because an API key, not a person, requested it; that is not editable. |
| Profile `HiBoss iOS AdHoc` | `KF83TB4BMD` | |
| Profile `HiBoss Widgets AdHoc` | `JP3ZJH7C7K` | |
| Profile `HiBoss iOS AppStore` | `23HB7UGHSC` | |
| Profile `HiBoss Widgets AppStore` | `8C7Q79AZ2Q` | |

Profiles are downloaded to `~/.asc/profiles/` and installed under
`~/Library/Developer/Xcode/UserData/Provisioning Profiles/` by UUID.

## Verified

An Ad Hoc archive builds and signs end to end
(`xcodebuild -configuration AdHoc ... archive`, ARCHIVE SUCCEEDED). The signed
bundle carries `application-identifier JHH9GC8Y8C.ai.hiboss.app`,
`aps-environment production`, and `com.apple.developer.team-identifier
JHH9GC8Y8C`, with the widget at `ai.hiboss.app.widgets`.

`macos/scripts/build-app.sh` defaults to ad-hoc signing so the script stays
portable for an open-source checkout. An ad-hoc signature has no stable
designated requirement, and the boss token lives in a plain login-keychain item
whose ACL is bound to one, so local builds prompt for keychain access after
every rebuild unless `HIBOSS_SIGNING_IDENTITY` names a real identity. That is
documented in the script header rather than fixed by hardcoding a personal
certificate name into a repo headed for open source.

## Blocked / manual steps

- **Developer ID Application cert cannot be created via API.** Apple restricts it
  to the Account Holder, and App Store Connect team API keys cap at ADMIN:
  "This request is forbidden for security reasons: This operation can only be
  performed by the Account Holder." A CSR + private key are already generated at
  `~/.asc/keys/devid-g2.{csr,key}`; upload the CSR at
  developer.apple.com/account/resources/certificates/add (Developer ID
  Application, G2 Sub-CA), then assemble the .p12 from the downloaded .cer.
- **APNs auth key must be created by hand** — no App Store Connect API endpoint
  and no `asc` command. developer.apple.com -> Keys -> enable APNs.

## Known consequences of the team switch

- **`security import -T /usr/bin/codesign` is not enough to stop the prompt.**
  Since macOS Sierra the key's *partition list* gates access too, and `-T` alone
  leaves it unset, so the first `codesign` run blocks on a GUI dialog with no
  output -- a build that looks hung. Either click "Always Allow" once, or run
  `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <login
  password> ~/Library/Keychains/login.keychain-db`, which needs the login
  password and so cannot be automated on someone's behalf.
- **Keychain items do not survive.** macOS service `ai.hiboss.island.stable` and
  the iOS keychain are gated on the signing team; every device re-authenticates.
- **Sparkle**: the first Developer-ID-signed build must be installed by hand.
  Sparkle only installs an update whose signature matches the running app
  (`macos/RELEASE.md`). Auto-updates resume from that build onward.
- **Push**: `boss_devices` stores `bundle_id` and `environment` per row
  (`server/migrations/0025_boss_devices.sql`), and the iOS client self-reports
  both (`PushManager.swift`), so the server needs no code change. Only the three
  worker secrets move: `APNS_TEAM_ID` -> `JHH9GC8Y8C`, plus a new `APNS_KEY_ID`
  and `APNS_AUTH_KEY`. Existing device tokens belong to the old app and die with
  it; rows self-prune on `BadDeviceToken`.
- **The APNs cutover is one-way and cannot be staged.** The server holds exactly
  one auth key (`env.APNS_KEY_ID`, singular) and a key can only push to its own
  team's app IDs, so old-app and new-app tokens cannot both be served. Worse,
  rollback does not exist: Cloudflare secrets are write-only, Apple serves a
  `.p8` once, and no old APNs key file survives on disk (checked). Therefore
  **install and register the new app first, then swap** -- doing it the other
  way opens a window with no working push and no way back.
  Use `wrangler secret bulk` rather than three `wrangler secret put` calls: the
  three values must move together, and between individual puts the worker runs
  a mismatched key/team pair that fails every push as `InvalidProviderToken`.
  All three are secrets, not `[vars]`, so no redeploy is needed.
- **Production APNs runs for the first time.** Both Ad Hoc and TestFlight force
  `aps-environment: production`, and `PushManager.environment` returns
  `production` for any non-DEBUG build. The server's production branch has never
  been exercised — verify it explicitly rather than assuming.
