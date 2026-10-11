KB consulted: `kb ios ui ux polish` and `kb 'iOS offline loading placeholder'`
matched the cold simulator demo-launch lesson and the state-field completeness
lesson. UI checks use `launchConfiguredDemo()` and inspect rendered recovery controls.

# iOS Today recovery states

## Findings

1. Offline and connecting header chips say "Checking coverage"
   (`ios/App/Home/Today/TodayHeader.swift`, `chips`). Name the connection state;
   retain coverage checking for a live stream with incomplete reads.
2. Connection failure hides the diagnostic, including session expiry
   (`ios/App/Home/HomeConnectionStatus.swift`, `notice(for:)`). Preserve the error
   alongside recovery instructions.
3. Failed empty attention shows loading placeholders above loaded results
   (`ios/App/Home/HomeAttentionRow.swift`, `HomeAttentionSection.body`). Reserve
   placeholders for a pending read, preserving real results in a terminal failure.
4. Disconnected Home offers Retry without an attached API
   (`ios/App/Home/HomeContent.swift`, `todayContent(now:)`);
   `InboxStore.retryConnection()` returns without an API. Offer Settings; show
   Retry only when an API can execute it; do not instruct a pull-to-refresh when
   no API is available.

The premise that a connection failure waits eight seconds before offering actions
is **REFUTED**: `PendingStateView` already reveals failures and actions immediately.
The all-clear gate remains conservative: an offline or incomplete snapshot cannot
show "Nothing needs you". Cached decisions and their answerability remain unchanged.

## Verification scope

These changes affect Today views only (T2). Verification covers the iOS unit target,
Today/Home UI classes, and screenshots in both appearances and languages with
accessibility text. No shared control, navigation, catalog, API, or widget changes
are required. Physical-device push and Live Activity behavior are outside this check.

Four regressions failed on baseline `52399e2`: preserved failure reason, connecting
header, disconnected recovery, and failed-page result reachability. The result bundle
is `/private/tmp/hiboss-ux-polish/before-retry.xcresult`. The original failure screenshot
shows three placeholders ahead of "Working now", with "Delivered" below the first screen.
The corrected default-size failure view brings both section headings above the tab bar.
Recovery buttons are at least 44 points tall and remain above the tab bar at
accessibility L in English and Simplified Chinese, light and dark.

The final T2 command, source HEAD, log, and result bundle are retained under
`/private/tmp/hiboss-ux-polish/final.{command,head,log,xcresult}`. Named before/after
images are exported using `ios/scripts/export-intermediate-shots.py`.

On source `bc99a374124e1219c4c45c79f924a62391410833`, the final T2 run passed
325 unit tests and 20 UI tests, with one UI test failing. The recovery matrix fails
at `HomeSimplificationUITests.swift:69`: tapping Settings in English at
accessibility L does not expose `settings-connection`. The preceding visibility,
button-height, and position assertions pass. The recorded tap lies inside the
Settings button frame; the following accessibility snapshot still shows Today.
The cause is unconfirmed, and T2 is not fully passing.

An isolated replay reproduced the failure in both English appearances. A temporary
Today-only layout using one `AnyLayout` and vertically stacked accessibility-size
actions also failed the same assertion. That experiment was reverted. The replay
and experiment each ran one test with zero passes and one failure; their artifacts
are `recovery-rerun.xcresult` and `recovery-layout.xcresult` under the same directory.
The experimental source diff is preserved as `rejected-layout.patch` there.

Further diagnosis can inspect the tap recording for a layout or state transition,
trace the Settings callback and sheet presentation, and compare baseline and current
behavior under identical stream-failure timing. No root cause is inferred from
the passing geometry assertions alone.
