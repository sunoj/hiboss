# macOS message notifications

The macOS app consumes the passive `GET /api/boss/stream?feed=true` feed separately
from the existing option stream. `OptionFlowStore` and the Island ask flow are unchanged.

## Behavior

- Only `agent_to_boss` messages without options produce system notifications.
  Expired questions retaining options are also excluded.
- Message IDs are deduplicated for the running app's lifetime, including reconnects.
  Messages received while the toggle is off are remembered and are not replayed on enable.
- Reconnects use the same fixed delay as `OptionFlowStore`, after errors and normal EOF.
- Titles contain the agent name and a session label when supplied. The current server
  feed does not join session labels; those messages display the agent name alone.
- Bodies collapse whitespace and truncate at 240 characters, including an ellipsis,
  without splitting Unicode grapheme clusters. Session IDs provide notification grouping;
  messages without sessions have no thread identifier.
- Clicking a notification opens All messages in the main History surface and fetches
  that message's detail directly. It does not depend on the message being in the latest
  History page. Lookup failures show an error with Retry and Close controls.
- The local preference defaults on and requests authorization on first launch or enable
  if permission is undetermined. Settings displays authorization state and refreshes it
  when active; denied permission exposes a System Settings Notifications button.

Quiet hours and priority filtering are out of scope. The Notifications pane states this
under the toggle. System notification preferences and Focus can still affect presentation.

The passive feed has no replay cursor and starts at connection time. Messages created
while the app is offline or between reconnects are not backfilled as notifications.
The app must be running to consume the feed. No server or APNs changes are required.

## Verification

- `cd HibossKit && swift test`: 105 passed (104 XCTest plus 1 Swift Testing), 0 failures.
  The feed transport test verifies the authenticated URL, inbox decoding, and delivery
  while the SSE connection remains open. Two decoder tests cover filtering and metadata.
- `cd macos && swift test --skip 'E2E|AttentionLayoutTests'`: 117 passed, 0 failures.
  Eleven notification tests cover option exclusion, direction, duplicate IDs, formatting,
  Unicode truncation, disabled-state suppression, authorization, reconnects, and cancellation.
- `cd macos && swift build`: passed.
- `HIBOSS_SIGNING_IDENTITY='Apple Development: Ming Sun (234582ZA6V)' bash macos/scripts/build-app.sh`:
  passed; produced `macos/dist/HiBoss Island.app` in this worktree. The bundle identifier
  is `ai.hiboss.island`. `codesign --verify --deep --strict` passed for the bundle and
  its nested components. Signing verifies packaging, not banner delivery.
- The complete macOS `swift test` command was not run: 41 E2E/UI tests are excluded by
  the mandatory remote-only execution rule. `grok-bot-chief` did not resolve;
  `grok-bot-twitter` was reachable but reported Linux and had no Swift executable.
- A live `hiboss send "ping"` banner and notification-click UI were not observed.
  The authorized remote hosts cannot run this macOS UI check. The built app was not
  launched locally, installed into `/Applications`, or substituted for the running app.

Build logs and test logs for this execution are in `/tmp/hiboss-kit-tests.log`,
`/tmp/hiboss-macos-tests.log`, `/tmp/hiboss-macos-build.log`, and
`/tmp/hiboss-bundle-build.log` on the development Mac. These are local artifacts.

The delivery adapter uses Apple's [notification center delegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate)
for foreground presentation and notification responses. Unit tests inject a fake center
and never request OS authorization or post real notifications.
