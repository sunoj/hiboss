# iOS Settings v2

KB consulted: `kb ios settings navigation intermediate states` returned the
demo-launch environment lesson and the cross-component regression lesson. UI
tests use `launchConfiguredDemo()`; verification includes the complete iOS suite.

## Baseline

Source baseline: `8bafbf17dced787c22be10a4c958e1d222a958cd`.
Screenshots are in [settings-v2/before](../ios/Screenshots/settings-v2/before/).
They show Settings at the top, middle and bottom, pairing, Mac review and code,
device requests and review, and the sign-out confirmation.

Settings has 13 source files and one long Form. In the demo fixture with quiet
hours enabled and notification permission unset, it has **22 rows**: connection
(2), device links (3), permission/status (2), routing (4), quiet hours (4), push
tiering (4), privacy/decision alerts (2), and sign-out (1). A configured session
also includes a variable device inventory; edits add a Save Changes row.

| Problem | Baseline evidence |
| --- | --- |
| Server and connection status give no next step | `SettingsView.swift:25–45`; `en-10-settings.png` |
| Three device cards repeat instructions before the flow starts | `SettingsView.swift:48–76`; `en-10-settings.png` |
| Permission, routing, timing and interruption rules compete on one page | `SettingsView.swift:86–110`; `en-11-settings-scrolled.png`, `en-12-settings-bottom.png` |
| Sign-out requires a long scroll | `SettingsView.swift:128–137`; `en-19-sign-out.png` |
| Fast loads show spinners immediately; long waits have no action | `PairDeviceView.swift:81`, `DeviceRequestsView.swift:58`, `MacSigninView.swift:57` |
| Mac and join-request decisions disable the entire review | `MacSigninView.swift:136`, `JoinRequestReviewView.swift:87` |
| Mac approval failure replaces the review | `MacSigninModel.swift:145–146` |

The baseline demo shows “Server —” because it uses fixture APIs without stored
credentials. This is not evidence of a live connection failure.

## Structure

A native Form has **five top-level rows**, in this order:

1. Connection — server and live status, with details and Reconnect.
2. Devices — pending count; pairing, Mac sign-in, requests and registered devices.
3. Notifications — permission and quiet-hours summary.
4. About — installed version and build.
5. Sign Out — the existing destructive confirmation.

Connection detail explains what to do: reconnect after a stream failure, wait
during connection, or sign in when no configuration exists. It retains the full
server URL, status, error and device-token notice. The demo identifies its sample
server explicitly.

Devices has one section of three entry points, followed by the existing device
inventory. Instructions belong beside the code or scan action. Pairing says this
phone stays signed in. Role-denied wording, QR/link handling, machine identity,
verification code, expiry and all confirmations retain their behavior. A pushed
join request still presents its review over the current tab.

Notifications answers “when will I be notified?” in one place: system permission
and registration, a summary of enabled priority rules, quiet hours and critical
bypass, decision alerts, and message privacy. Changes are explicit drafts with
Save Changes, a saved confirmation and retry after failure. Navigation preserves
the draft; controls remain usable during saving and later edits remain unsaved.

**Delivery details** sits one level deeper under Notifications. It contains the
existing per-priority phone delivery/sound/interruption rules and external
channel routing. These are occasional configuration tasks rather than daily
phone actions. Routing chooses Discord, Telegram and API channels; it does not
choose individual recipients or this phone's push permission. Phone tiering is
relevant to the boss, so its current effect is summarized on Notifications while
the matrix stays in detail. Neither capability is removed.

## Task cost

Counts start on another tab, include opening Settings, and exclude scrolling,
text entry, QR scanning and external-device actions. The before fixture already
has quiet hours enabled; “mute tonight” means adjust the recurring window, not a
new one-night timer. There is no existing one-night mute capability.

| Task | Before taps | After taps | Change |
| --- | ---: | ---: | --- |
| Check server and connection | 1 | 1 | Summary remains on the root; full details cost 2 |
| Show pairing code | 2 | 3 | Devices groups three related flows |
| Approve a device request | 4 | 5 | Review and explicit approval remain |
| Toggle scheduled mute and save | 3 | 4 | Notifications groups timing and delivery |
| Change urgent phone delivery and save | 4 | 6 | Notifications → Delivery details → priority menu → choice → save |
| Change urgent external channel and save | 4 | 6 | Same detail level; recipients are not editable here |
| Sign out, including confirmation | 3 | 3 | Same confirmation, no long scroll |

## Capability map

| Capability | Destination |
| --- | --- |
| Server, stream status, reconnect, token exchange notice | Connection |
| Pair code, QR, copy feedback, expiry, redemption, role denial | Devices → Pair another device |
| Scan Mac request, origin, expiry, approve/reject, code warning, Done | Devices → Sign in a Mac |
| Pending count, refresh, missing-code warning, approve/reject | Devices → Device Requests → review |
| Registration, device name, inventory and confirmed revocation | Devices, existing shared inventory section |
| Permission and system-settings action, registration result | Notifications → This phone |
| Quiet-hours enable/start/end/timezone/critical bypass | Notifications → Quiet Hours |
| Decision alerts and private notifications | Notifications |
| Priority delivery, sound and interruption level | Notifications → Delivery details |
| Discord/Telegram/API by priority | Notifications → Delivery details |
| Load/save failure, draft retention, Save Changes | Notifications and Delivery details |
| App version/build | About |
| Sign-out and its destructive confirmation | Settings root |

## Intermediate states

Screens keep context immediately. A progress indicator appears only after
300 ms, and a wait lasting eight seconds adds plain words and an action. A
request or save disables its own action, not the page or navigation. Pairing
expiry keeps its fresh-code action. Device review retains all identity and code
information during approval. Permission state distinguishes OS authorization
from registration and refreshes when returning from system Settings.

The Mac model has no polling loop: it loads the scanned request and approves or
rejects it. It drops review state on approval failure; presentation can retain
the scanned summary without changing its API calls or retry behavior. The join
request data model exposes a host and creation time, but no IP or expiry fields;
the redesign preserves the information actually available rather than inventing
security metadata. These are properties of the existing flows.

## Before/after evidence

| Measure | Before | After |
| --- | --- | --- |
| Root rows (demo, quiet hours enabled) | 22 | Target: 5 |
| Device entry sections on root | 3 | Target: 1 Devices row |
| Notification control sections on root | 5 | Target: 1 Notifications row |
| Sign-out confirmation steps | 2 after Settings | Unchanged |
| Capability removal | None | None planned |
| Appearance/language/text coverage | Baseline English | Light/dark × en/zh-Hans × default/accessibility L |

After screenshots and measured verification are recorded here after implementation.
