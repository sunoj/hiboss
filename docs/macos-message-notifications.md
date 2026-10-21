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

The delivery adapter uses Apple's [notification center delegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate)
for foreground presentation and notification responses. Unit tests inject a fake center
and never request OS authorization or post real notifications.
