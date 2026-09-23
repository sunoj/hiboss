# HiBoss Island for macOS

HiBoss Island is a focused macOS client with a main window for recent agent and
boss messages. When an agent sends a message containing `metadata.options`, the
app also presents a choice picker at the top center of the active display or in a
standard movable window. Selecting an option replies through the existing Boss API.

## Requirements

- macOS 14 or newer
- A running HiBoss server
- A Boss Token with access to at least one agent

The app stores the server URL in user defaults and the Boss Token in the macOS
Keychain. Its main window fetches the latest 100 messages from the server and does
not persist a separate local history.

Double-clicking a History row opens its detail sheet. Message content is the primary
section, active choices follow it, and transport/session metadata is available in a
collapsed **Details** disclosure. Text remains selectable inside the detail sheet.

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

The app opens a resizable main window with a Reminders-inspired overview:
**Needs You**, **Automatic**, **Waiting on you**, **High priority**, **All messages**,
and **Completed**, followed by session lists. Counts match each destination and
reflect recently loaded messages. Below 760 points, the **Overview** toolbar button
switches between the overview and the selected surface. Attention areas narrower
than 720 points show questions and details in a single column; **All questions**
returns to the list. The minimum main window is 480 × 400.

Question text wraps and scrolls above a persistent reply composer. Use **Send reply**
or Command-Return to submit custom instructions. Drafts stay with their question
when selecting another category or resizing, for the main window's lifetime.
History detail shares those drafts and supports custom replies to pending questions.
Failed submissions retain the draft and show a retry message. See the
[overview contract](../docs/macos-information-redesign.md) for count definitions.

On first launch, enter the server root URL and Boss Token, then select
**Save & Connect**. Presentation settings let users choose Island or Window mode
and independently show or hide the menu bar icon. Closing the main window keeps
the listener running; clicking the Dock icon opens it again. The menu bar icon uses
a native status item so hiding it does not remove the app's SwiftUI scene. Keychain
loading happens after launch and never blocks window creation. The app reconnects to
`GET /api/boss/stream?options=true` when the server closes its five-minute SSE stream.

Every connected client receives each active option independently. When any client
selects an option, the server accepts only the first selection and broadcasts a
`resolved` event so all other clients withdraw the picker within one polling cycle.
Unanswered options withdraw locally at their exact `expires_at` timestamp.

**Pair another device** creates a QR code containing the server URL and a short-lived
single-use code, never a Boss Token. The sheet observes redemption and replaces the
QR with the connected device label. Pairing another device does not rotate or expose
the Mac's existing token.

To generate a token for an existing boss, call the server endpoint with an admin
Boss Token:

```bash
curl -X POST \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  "https://<HIBOSS_SERVER>/api/bosses/<BOSS_ID>/token"
```

Use the returned `token` value in the app. A boss with the `viewer` role can see
messages but cannot send option replies, so use an `admin` or `manager` boss.

An admin bearer can revoke sibling devices. The five-minute, single-use pairing
code protects an unredeemed QR code; it does not restrict a bearer token that has
already been issued.

Break-glass recovery is a manual database operation if all live tokens are lost,
a rotated secret is discarded, or rotation revokes tokens before minting fails.
Generate a new bearer locally, hash it with SHA-256, insert only the hash into
`boss_tokens`, and keep the bearer private:

```bash
TOKEN="hb_boss_$(openssl rand -hex 32)"
HASH="$(printf %s "$TOKEN" | shasum -a 256 | awk '{print $1}')"
npx wrangler d1 execute hiboss-db --remote --command "INSERT INTO boss_tokens (boss_id, label, token_hash) VALUES ('<BOSS_ID>', 'break-glass', '$HASH')"
echo "$TOKEN"
```

## Verify

```bash
cd macos
swift test
```

The end-to-end tests cover option filtering, sequential presentation, successful
replies, duplicate suppression, global resolution, exact expiry, recoverable reply
failures, attention draft isolation, reply editor bounds at four window sizes,
history decoding, persisted presentation preferences, and background
survival after the last window closes.
