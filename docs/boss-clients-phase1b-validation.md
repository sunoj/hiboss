# Boss clients phase 1b validation

Validated on 2026-09-11 in the `feat/native-boss-clients` worktree.
No server code, option store/stream, or pairing redemption was changed.
No app was installed, replaced, or launched. No push or PR was created.

## Implementation

- HibossKit owns the client ID/kind/inventory/grant models, authenticated
  create/list/revoke calls, and a `BossClientsServing` protocol in `Domain.swift`.
  The protocol is separate from message streaming so device management does not
  change the option-stream contract.
- Manual login verifies the pasted bearer before minting an `ios` or `macos`
  client. Only the returned token is persisted on success. An exchange failure
  retains the verified pasted token and displays a localized compatibility notice.
  Verification failure never persists the pasted token or attempts exchange.
- macOS treats a changed token or server as manual login. Reconnect and preference
  saves with the existing connection do not create extra clients. Devices uses
  the saved connection even while the Connection pane contains unsaved edits.
- Labels default to `Host.current().localizedName` (with `Mac` if unavailable)
  and `UIDevice.current.name`. Both are editable before manual connection.
- iOS restoration and pairing retain their existing token behavior. The fallback
  notice appears immediately after manual login and remains in Settings for the
  current app session. macOS shows it in the Connection pane.
- A shared native Form section shows device kind icons, labels, last activity,
  push/signing attachments, current-device markers, and revoked inventory.
  Revoke buttons require confirmation and are absent for current/revoked clients.
  A successful revocation remains reflected locally if the subsequent refresh fails.
- Devices sits immediately after Connection in the macOS sidebar and directly in
  iOS Settings. All new catalog entries have English and Simplified Chinese values;
  existing entries and other locales are preserved.

## Verification

| Command | Result |
| --- | --- |
| `cd HibossKit && swift test` | 120 passed: 119 XCTest + 1 Swift Testing; 0 failures |
| `cd macos && swift test --skip 'E2E\|AttentionLayoutTests'` | 122 passed; 0 failures |
| `cd macos && swift build` | Passed |
| `bash macos/scripts/build-app.sh` | Passed; ad-hoc signed worktree artifact |
| `cd ios && xcodegen generate` | Passed; project diff only adds the new test source |
| `xcodebuild -scheme HiBoss -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/phase1b -clonedSourcePackagesDirPath build/SourcePackages build` (in `ios/`) | Passed |
| Same Xcode settings with `-only-testing:HiBossTests build-for-testing` | Passed; four new iOS connection-store tests compiled, zero executed |

New coverage: seven HibossKit API/decoder tests, five device-store tests, five
macOS login-store tests, and four iOS login-store tests. Cases cover request shape,
authentication, nullable/SQLite/ISO timestamps, current/revoked metadata, credential
redaction, fresh-token persistence, fallback notices, rejected credentials,
unchanged restoration, revoke protection, failure recovery, and saved credentials.
The existing macOS sidebar-order assertion now includes Devices after Connection.

The installed simulator is iPhone 17 on iOS 26.5; iPhone 16 is unavailable.
The iOS test build also compiles existing UI-test targets because they belong to
its scheme, but does not execute them. Existing concurrency warnings remain in
pairing-camera and UI-test code; these files were not changed.

Native visual/E2E checks were not run. `grok-bot-twitter` is reachable but runs
Linux, and `grok-bot-chief` did not resolve. The authorized remote hosts therefore
could not run Apple-native UI checks. No local E2E fallback was used. iOS unit tests
were built rather than executed to avoid installing/launching the app.

## Artifacts

Paths are relative to this worktree, not hosted links:

- macOS executable: `macos/.build/arm64-apple-macosx/debug/HibossIsland`
- macOS app bundle: `macos/dist/HiBoss Island.app`
- iOS simulator app: `ios/build/phase1b/Build/Products/Debug-iphonesimulator/HiBoss.app`
- iOS unit bundle: `ios/build/phase1b/Build/Products/Debug-iphonesimulator/HiBoss.app/PlugIns/HiBossTests.xctest`

Local logs: `/tmp/hiboss-phase1b-kit.log`, `/tmp/hiboss-phase1b-macos.log`,
`/tmp/hiboss-phase1b-macos-build.log`, `/tmp/hiboss-phase1b-macos-bundle.log`,
`/tmp/hiboss-phase1b-ios-build.log`, and `/tmp/hiboss-phase1b-ios-tests-build.log`.

HiBoss panel delivery was unavailable: `panel doctor` reported no resolved
execution session, and boss discovery returned HTTP 401. Progress and results
were delivered in the task conversation.
