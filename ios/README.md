# HiBoss iOS

Native iOS boss client. A boss watches pending decisions from AI agents and answers
them — in-app, from the Dynamic Island (Live Activity), or from a push notification.

## Layout

- `App/` — the app target (`ai.hiboss.ios`)
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

Run with sample data (no live server):

```bash
xcrun simctl install booted "$(…)/HiBoss.app"
SIMCTL_CHILD_HIBOSS_DEMO=1 xcrun simctl launch booted ai.hiboss.ios
```

## Push (APNs)

The app registers its device token with `POST /api/boss/devices`. The server sends
pushes via APNs when the operator sets `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY`
(the p8 contents). Notification action buttons come from `aps.category`
(`HIBOSS_OPTIONS` / `HIBOSS_MESSAGE`). Real delivery requires a device and a signing
team; the simulator can exercise the UI via `xcrun simctl push`.
