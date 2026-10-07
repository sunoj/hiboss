# iOS Settings v2

KB consulted: `kb ios settings navigation intermediate states` returned the
demo-launch environment lesson and the cross-component regression lesson. UI
tests use `launchConfiguredDemo()`; verification includes the complete iOS suite.

## Baseline

Source baseline: `8bafbf17dced787c22be10a4c958e1d222a958cd`.
Screenshots are in [settings-v2/before](../ios/Screenshots/settings-v2/before/).
They show Settings at the top, middle and bottom, pairing, Mac review and code,
the Mac scan introduction, device requests and review, and the sign-out confirmation.
The scan introduction was supplemented from unchanged baseline app sources.

Settings has 13 source files, 1,585 lines, and one long Form. In the demo fixture with quiet
hours enabled and notification permission unset, it has **22 rows**: connection
(2), device links (3), permission/status (2), routing (4), quiet hours (4), push
tiering (4), privacy/decision alerts (2), and sign-out (1). A configured session
also includes a variable device inventory; edits add a Save Changes row.

| Problem | Baseline evidence |
| --- | --- |
| Server and connection status give no next step | `SettingsView.swift:25–45`; `en-10-settings.png` |
| Device cards repeat instructions | `SettingsView.swift:48–76`; `en-10-settings.png` |
| Notification rules compete on one page | `SettingsView.swift:86–110`; `en-12-settings-bottom.png` |
| Sign-out requires a long scroll | `SettingsView.swift:128–137`; `en-19-sign-out.png` |
| Loading flashes; long waits have no action | `PairDeviceView.swift:81`, `MacSigninView.swift:57` |
| Decisions disable the whole review | `MacSigninView.swift:136`, `JoinRequestReviewView.swift:87` |
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
text entry, QR scanning and external-device actions. The mute task starts with
quiet hours off and enables the saved recurring window; there is no existing
one-night mute capability. The row-count fixture has quiet hours on so the time
and critical-bypass controls are visible.

| Task | Before taps | After taps | Change |
| --- | ---: | ---: | --- |
| Check server and connection | 1 | 1 | Summary remains on the root; full details cost 2 |
| Show pairing code | 2 | 3 | Devices groups three related flows |
| Approve a device request | 4 | 5 | Review and explicit approval remain |
| Mute tonight using the saved schedule | 3 | 4 | Enables recurring quiet hours and saves |
| Change urgent phone delivery and save | 4 | 6 | One deeper page before the priority menu and Save |
| Change urgent external channel and save | 4 | 6 | One deeper page; recipients remain unavailable |
| Choose urgent-push recipients | Unavailable | Unavailable | No recipient editor exists |
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
save disables only Save Changes. Approval disables the pending request's
decision controls, retaining the model's single-decision guard, while code,
details, Close and navigation remain usable. Pairing
expiry keeps its fresh-code action. Device review retains all identity and code
information during approval. Permission state distinguishes OS authorization
from registration and refreshes when returning from system Settings.
The permission wait ends once authorization is granted, even while registration
continues with its own status. Decision alerts retain their existing immediate
effect on local presentation; their server preference still uses Save Changes.

The Mac model has no polling loop: it loads the scanned request and approves or
rejects it. It drops review state on approval failure; presentation can retain
the scanned summary without changing its API calls or retry behavior. The join
request data model exposes a host and creation time, but no IP or expiry fields;
the redesign preserves the information actually available rather than inventing
security metadata. These are properties of the existing flows.

## Before/after evidence

| Measure | Before | After |
| --- | --- | --- |
| Root rows (demo, quiet hours enabled) | 22 | 5, asserted by a UI test |
| Device entry sections on root | 3 | 1 Devices row |
| Notification control sections on root | 5 | 1 Notifications row |
| Sign-out confirmation steps | 2 after Settings | Unchanged |
| Capability removal | None | None |
| Appearance/language/text coverage | Baseline English | Light/dark × en/zh-Hans × default/accessibility L |

Sign Out is visible without scrolling at both default and accessibility L text
sizes on the iPhone 17 simulator. Details require more taps, as measured above;
the improvement is a shorter root and clearer grouping rather than fewer taps
for every task.

Two editor regressions are covered by focused tests: an earlier save response
must not erase edits made while saving, and quiet-hours pickers must display the
stored wall-clock digits. The previous date conversion used year 1 and inherited
historical local offsets; the picker now uses a modern UTC anchor while the
stored `HH:mm` and timezone remain unchanged.

Large-text screenshot review also exposed a truncated external-channel summary.
Routing now uses native `LabeledContent` with wrapping values.

The [after gallery](../ios/Screenshots/settings-v2/after/) contains 144 images:
18 stops in each light/dark × en/zh-Hans × default/accessibility L combination.
Delivery detail images were refreshed after restoring their menu indicators.
The [state gallery](../ios/Screenshots/settings-v2/after/states/) has nine images
covering waits, denial, failures, empty requests and retained approval details.

| Comparison | Before | After |
| --- | --- | --- |
| Root | [22 rows][before-root] | [5 rows][after-root] |
| Large-text root | Not captured | [Sign Out remains visible][after-large] |
| Notification controls | [Long-page controls][before-notify] | [Overview][after-notify] |
| Large-text channel summary | Not captured | [Complete values and menu indicators][after-delivery] |

[before-root]: ../ios/Screenshots/settings-v2/before/en-10-settings.png
[after-root]: ../ios/Screenshots/settings-v2/after/en-10-settings.png
[after-large]: ../ios/Screenshots/settings-v2/after/en-axL-10-settings.png
[before-notify]: ../ios/Screenshots/settings-v2/before/en-12-settings-bottom.png
[after-notify]: ../ios/Screenshots/settings-v2/after/en-12-notifications.png
[after-delivery]: ../ios/Screenshots/settings-v2/after/en-axL-12-delivery-bottom.png

Commands, iteration counts and final suite evidence are in
[verification](ios-settings-v2-verification.md).

No capability was removed. No shared component, HibossKit, server route, CLI or
macOS behavior changed. The existing registered-device inventory was moved intact.
Open product questions are whether a one-night mute action or per-device urgent
recipients should exist; neither feature is available in the current API/UI.
