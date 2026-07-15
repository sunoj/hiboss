# HiBoss Island for macOS

HiBoss Island is a single-purpose macOS client. When an agent sends a HiBoss
message containing `metadata.options`, the app presents a choice picker either at
the top center of the active display or in a standard movable window. Selecting an
option replies to the original message through the existing Boss API.

## Requirements

- macOS 14 or newer
- A running HiBoss server
- A Boss Token with access to at least one agent

The app stores the server URL in user defaults and the Boss Token in the macOS
Keychain. It does not keep a local message history.

## Build and run

```bash
cd macos
./scripts/build-app.sh
open "dist/HiBoss Island.app"
```

The build script uses a stable Apple Development identity. Set
`HIBOSS_SIGNING_IDENTITY` to use a different installed code-signing identity.
The bundled app icon depicts a relaxed boss on a tiny tropical island and is
compiled from the source asset catalog under `Resources/Assets.xcassets`.

On first launch, enter the server root URL and Boss Token, then select
**Save & Connect**. Presentation settings let users choose Island or Window mode
and independently show or hide the menu bar icon. The app shows a Dock icon when
needed so settings remain reachable. It automatically reconnects to
`GET /api/boss/stream?options=true` when the server closes its five-minute SSE stream.

Every connected client receives each active option independently. When any client
selects an option, the server accepts only the first selection and broadcasts a
`resolved` event so all other clients withdraw the picker within one polling cycle.
Unanswered options withdraw locally at their exact `expires_at` timestamp.

To generate a token for an existing boss, call the server endpoint with an admin
agent key or admin Boss Token:

```bash
curl -X POST \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  "https://<HIBOSS_SERVER>/api/bosses/<BOSS_ID>/token"
```

Use the returned `token` value in the app. A boss with the `viewer` role can see
messages but cannot send option replies, so use an `admin` or `manager` boss.

## Verify

```bash
cd macos
swift test
```

The end-to-end tests cover option filtering, sequential presentation, successful
replies, duplicate suppression, expired options, recoverable reply failures, and
persisted presentation preferences.
