# HiBoss iOS

Native iOS boss client. A boss watches pending decisions from AI agents and answers
them — in-app, from the Dynamic Island (Live Activity), or from a push notification.

## Layout

- `App/` — the app target (`ai.hiboss.app`)
  - `Theme/` — design tokens ported from the shared design system (light + dark, priority colors)
  - `Connection/` — server URL + Keychain token → `ConnectionStore`
  - `Inbox/` — Inbox screen: live pending decisions over SSE, option/reply actions, countdowns
  - `Messages/`, `Settings/`, `Onboarding/` — the other tabs + first-run connect
  - `LiveActivity/` — starts/updates/ends decision Live Activities from the inbox
  - `Push/` — remote-notification auth, category/action registration, action → reply
  - `Preview/DemoData.swift` — sample data for `HIBOSS_DEMO=1` runs (no server needed)
- `Widgets/` — widget extension: the decision Live Activity (lock screen + Dynamic Island)
- `Shared/` — attributes + App Intent + storage helper, compiled into both targets

Domain models, the boss API client, and the option flow come from the shared
`HibossKit` package (`../HibossKit`).

## Pairing and restoration

To sign in a new iPhone, open **Pair another device** on a signed-in iPhone
(Settings) or **Pair a new device…** on a signed-in Mac (Settings → Connection), then
tap **Scan a code** on the new iPhone's connect screen. Entering a server URL and Boss
Token remains the secondary path.

The QR scanner accepts `hiboss://pair` links. A link contains the server URL and a
five-minute, single-use pairing code; it does not contain a Boss Token. Parsing lives
in HibossKit (`PairingPayload`), shared with the Mac: a server that is not `https` is
rejected, except `http://localhost` and `http://127.0.0.1`. The app fills the scanned
server URL before redemption, registers its Secure Enclave signing key, and stores
the resulting device token in Keychain. Restoration requires both a valid stored URL
and token, so an orphan token cannot skip onboarding or appear as a valid login.

**Pair another device** issues a code with `POST /api/boss/pairing`, shows the QR and a
copyable link (a Mac pastes it into **Pair with Code**), and polls
`POST /api/boss/pairing/status` until the code is redeemed or expires. A server answer
of HTTP 403 shows "Your role cannot pair devices".

`POST /api/bosses/<BOSS_ID>/token` is not an onboarding route: it rotates the boss's
token and revokes every device of that boss. See "Rotate all tokens" in
`macos/README.md`.

Onboarding, lock-screen Live Activities, and Dynamic Island presentations use the
shared image-backed HiBoss brand icon. Notification taps resolve the message through
the authenticated API and present the same scrollable detail surface as in-app rows.

## Build & run

```bash
brew install xcodegen          # once
cd ios
xcodegen generate              # regenerate HiBoss.xcodeproj from project.yml
open HiBoss.xcodeproj           # or build from the CLI:
xcodebuild -project HiBoss.xcodeproj -scheme HiBoss \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

Install a development build on a connected iPhone. The Debug configuration disables signing
and leaves the identity empty so simulator builds need no certificate, so a device build
overrides all three settings. `DEVELOPMENT_TEAM` must be global because HibossKit's package
targets are signed too:

```bash
xcodebuild -project HiBoss.xcodeproj -scheme HiBoss -configuration Debug \
  -destination "platform=iOS,id=<device UDID>" -derivedDataPath build/device \
  -allowProvisioningUpdates \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=JHH9GC8Y8C build
xcrun devicectl device install app --device <device UDID> \
  build/device/Build/Products/Debug-iphoneos/HiBoss.app
```

`xcrun devicectl list devices` prints the UDID. Start from a clean `-derivedDataPath`: an
incremental build made without signing is not re-signed. A Debug build registers for the
sandbox APNs environment, and it replaces a TestFlight or App Store install of the same bundle
identifier.

Run with sample data (no live server):

```bash
xcrun simctl install booted "$(…)/HiBoss.app"
SIMCTL_CHILD_HIBOSS_DEMO=1 xcrun simctl launch booted ai.hiboss.app
```

Prefer `SIMCTL_CHILD_*` (per-launch only). Do **not** `launchctl setenv HIBOSS_DEMO_*`
inside the simulator — those values stick on the device and every later UI-test / demo
launch inherits them. If you already did, clear with:

```bash
xcrun simctl spawn booted launchctl unsetenv HIBOSS_DEMO_SESSION
xcrun simctl spawn booted launchctl unsetenv HIBOSS_DEMO_OPEN
xcrun simctl spawn booted launchctl unsetenv HIBOSS_DEMO_RESOLVED
xcrun simctl spawn booted launchctl unsetenv HIBOSS_TAB
```

Deep-link flags (mutually exclusive; OPEN > RESOLVED > SESSION):

- `HIBOSS_DEMO_OPEN=<message-id>` — message detail
- `HIBOSS_DEMO_RESOLVED=1` — Resolved list
- `HIBOSS_DEMO_SESSION=1` — `sess-deploy` / prod-release transcript
- `HIBOSS_TAB=progress` — select the Progress tab
- `HIBOSS_DEMO_EMPTY=1` — show the settled, all-clear Home

## Push (APNs)

The app registers its device token with `POST /api/boss/devices`. The server sends
pushes via APNs when the operator sets `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY`
(the p8 contents). Notification action buttons come from `aps.category`
(`HIBOSS_OPTIONS` / `HIBOSS_MESSAGE`). Real delivery requires a device and a signing
team; the simulator can exercise the UI via `xcrun simctl push`.
