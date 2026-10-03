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

Session and history messages are readable directly in the main window. Ordinary
messages show their full body and supporting content with selectable text. Messages
longer than 1,200 characters or 14 explicit lines start with a short preview and
expand or collapse in place. Search reveals the full matching message, including
matches in supporting content. Message clicks and double-clicks never open details.

Choices, option images, and custom replies stay inside each message. Reply drafts
survive navigation; failed replies retain their text and show an inline retry error.
Command-Return sends only from the focused reply editor. Transport metadata and
closed choices remain available in inline disclosures.

## Build and run

```bash
cd macos
./scripts/build-app.sh
open "dist/HiBoss Island.app"
```

The build script defaults to ad-hoc signing. Set `HIBOSS_SIGNING_IDENTITY` to
an installed code-signing identity; use the same identity as the installed app
when replacing it locally to preserve its signing identity.
The bundled app icon depicts a relaxed boss on a tiny tropical island and is
compiled from the source asset catalog under `Resources/Assets.xcassets`.

The app opens a native workspace with a compact sidebar: **Dashboard**, **Needs
You**, **All messages**, **Completed**, decision filters, and searchable session
history. The dashboard shows the next three decisions above the live task wall.
Counts reflect loaded recent messages; overlapping filters are not additive.
Below 760 points, **Overview** switches between navigation and content. Dashboard
details use the full content area below 900 points of content width and an inspector
above it. The minimum window is 480 × 400. Command-R refreshes the current surface.

Question text wraps and scrolls above a persistent reply composer. Use **Send reply**
or Command-Return to submit custom instructions. Drafts stay with their question
when selecting another category or resizing, for the main window's lifetime.
Inline history replies share those drafts and support custom replies to pending questions.
Failed submissions retain the draft and show a retry message. See the
[overview contract](../docs/macos-information-redesign.md) for count definitions.

On first launch, open **Settings → Connection** and choose **Pair with Code…**.
Paste a `hiboss://pair?server=…&code=…` link, or type the server and the one-time
code, then confirm with the button that names the server host. **Use a Boss Token**
stays available as the secondary path: enter the server root URL and token, then
select **Save & Connect**. Presentation settings let users choose Island or Window mode
and independently show or hide the menu bar icon. Closing the main window keeps
the listener running; clicking the Dock icon opens it again. The menu bar icon uses
a native status item so hiding it does not remove the app's SwiftUI scene. Keychain
loading happens after launch and never blocks window creation. The app reconnects to
`GET /api/boss/stream?options=true` when the server closes its five-minute SSE stream.

Every connected client receives each active option independently. When any client
selects an option, the server accepts only the first selection and broadcasts a
`resolved` event so all other clients withdraw the picker within one polling cycle.
Unanswered options withdraw locally at their exact `expires_at` timestamp.

### Pairing a device

A signed-in device issues the code: **Pair another device** on iPhone (Settings) or
**Pair a new device…** on the Mac (Settings → Connection). Both call
`POST /api/boss/pairing` and show a QR code plus a copyable `hiboss://pair` link that
carries the server URL and a five-minute, single-use code, never a Boss Token. The
issuing screen polls `POST /api/boss/pairing/status` and replaces the QR with the
connected device label. Pairing does not rotate or expose the issuer's token. A role
the server refuses (HTTP 403) shows "Your role cannot pair devices".

The new Mac redeems the code with `POST /api/pairing/redeem`
(`{"code", "device_label"}`) and stores the returned token in Keychain, as a manual
login does. The app registers the `hiboss://` URL scheme: a clicked `hiboss://pair`
link opens the redeem sheet pre-filled and never redeems until the confirm button,
which names the server host, is clicked. A link whose server is not `https` is
rejected, except `http://localhost` and `http://127.0.0.1`. A boss with the `viewer`
role can see messages but cannot send option replies.

### Rotate all tokens (revokes every device of this boss)

`POST /api/bosses/<BOSS_ID>/token` mints a new token and revokes every existing token
of that boss, signing out all of its devices. Use it only to rotate credentials, not
to onboard a device:

```bash
curl -X POST \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  "https://<HIBOSS_SERVER>/api/bosses/<BOSS_ID>/token"
```

Sign the devices back in afterwards with **Use a Boss Token** on one device and
pairing for the rest.

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

Build with `swift build --package-path macos` and test with
`swift test --package-path macos`. See the
[workspace contract](../docs/macos-information-redesign.md) for layout, decision
rules, and verification scope.
