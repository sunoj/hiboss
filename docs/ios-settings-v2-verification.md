# Settings v2 verification

KB consulted: `kb ios settings navigation intermediate states` matched demo
launch environment loss and cross-component regression coverage.
`kb ios xctest launch stalled` found the same launch lesson, with no separate
startup remedy.

All builds and tests ran locally on `HiBoss-UX-17`, an iPhone 17 simulator
running iOS 27.0. There was no remote build HEAD. Baseline runs used `8bafbf1`
with screenshot-test additions; implementation iterations used `93685a0` plus
uncommitted changes. Follow-up iterations used `3646f74` plus uncommitted changes.
The final suite ran on clean, committed source at
`c83d58cbc0ff31d41db4c903ea437307825079e9`.

## Iteration results

Result bundles and command-header logs use the prefix
`/private/tmp/hiboss-settings-` and the names below.

| Run | Passed | Failed | Evidence |
| --- | ---: | ---: | --- |
| baseline | 0 | Build failure | Actor-isolated `XCUIApplication` default in test harness |
| baseline2 | 0 | 1 | Harness looked for virtualized Sign Out before scrolling |
| baseline3 | 2 | 0 | Baseline tour and pairing expiry |
| focused1 | 12 | 2 | Switch-label tap did not change its value |
| focused2 | 0 | 1 startup error | Canceled before XCTest started |
| focused3 | 0 | Build failure | Extracted Mac details needed the timeline's `now` parameter |
| focused4 | 15 | 2 | Same switch-label tap; assertion now verifies the switch changes |
| save5 | 6 | 0 | Save failure/long wait, Mac failure, request approval/load/empty states |
| focus6 | 0 | 1 startup error | Canceled host with no XCTest library loaded |
| focus7 | 11 | 0 | Eight unit tests and three save/delivery UI tests |
| regression-red | 0 | 1 startup error | Canceled host with no XCTest library loaded |
| regression-red2 | 0 | 2 expected | Previous save overwrite and year-1 date behavior restored |
| regression-green | 3 | 0 | Both fixes restored; delivery menu also exercised |
| baseline-intro | 1 | 0 | Mac introduction from unchanged baseline app sources |
| final-focused | 9 | 0 | Final permission/preference unit tests and delivery UI test |
| full | 0 | 1 startup error | Committed `3646f74`; host launched without XCTest |
| full-retry | 235 | 1 | `3646f74`; Progress initial data missed the demo's startup window |
| permission-red | 0 | 1 startup error | Canceled host with no XCTest library loaded |
| permission-red2 | 1 | 1 expected | Old permission wait detected; corrected Progress test passed |
| permission-green | 0 | 1 startup error | Canceled host with no XCTest library loaded |
| permission-green2 | 10 | 0 | Nine Settings unit tests and the Progress refresh UI test |
| final-full | 237 | 0 | `c83d58c`; 168 unit tests and 69 UI tests, without retries |

The canceled runs report a synthetic “Testing was canceled” failure in
xcresult, rather than an executed failing test. Stack samples of the two
later hosts contained neither XCTest nor `HiBossTests`. Retrying the same test
configuration started XCTest successfully. No test was skipped to bypass a
failure.

## Commands

The common command and filters reproduce the recorded xcodebuild invocations;
the original command headers are retained in each `.log`. Paths are abbreviated
below using shell variables:

```sh
XCODE=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
OUT=/private/tmp/hiboss-settings
UNIT=HiBossTests
UI=HiBossUITests
NAV=$UI/SettingsNavigationUITests
PREF=$UNIT/SettingsPreferencesTests
TOUR=$UI/SettingsTourUITests
PERM=$UNIT/SettingsPermissionTests
MAC=$UI/MacSigninUITests
```

Before the verification wrapper existed, the common arguments were:

```sh
cd ios
"$XCODE" test -project HiBoss.xcodeproj -scheme HiBoss \
  -destination 'platform=iOS Simulator,name=HiBoss-UX-17' \
  -derivedDataPath /private/tmp/hiboss-settings-v2-dd \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath "$OUT-<run>.xcresult" <filters>
```

Filters for those invocations:

| Runs | `-only-testing:` values, in order |
| --- | --- |
| baseline, baseline2 | `$TOUR/testEnglish` |
| baseline3 | `$TOUR/testEnglish`, `$UI/UXTourUITests/testTourPairingExpired` |
| focused1, focused3 | `$PREF`, `$NAV`, `$MAC`, `$TOUR/testEnglish` |
| focused2 | `$PREF`, then the first two save UI filters below |
| focused4 | `$PREF`, `$PERM`, `$NAV`, `$MAC`, `$TOUR/testEnglish` |

The `save5` invocation used these filters, in order:

```sh
-only-testing:$NAV/testFailedSaveKeepsInputAndNavigationKeepsTheDraft
-only-testing:$NAV/testLongSaveDisablesOnlySaveAndAllowsAnotherEdit
-only-testing:$NAV/testFailedMacApprovalKeepsTheScannedIdentity
-only-testing:$NAV/testApprovalInFlightKeepsTheCodeAndCloseUsable
-only-testing:$NAV/testEmptyDeviceRequestsExplainWhatWillAppear
-only-testing:$NAV/testDeviceRequestLoadFailureOffersRetry
```

The wrapper records the exact invocation in `.command` and the local HEAD in
`.head`. It uses the same common xcodebuild arguments above. From the repo root:

```sh
ios/scripts/settings-tests.sh "$OUT-focus6" HiBoss-UX-17 \
  -only-testing:$PREF -only-testing:$UNIT/SettingsPermissionTests \
  -only-testing:$NAV/testPriorityDeliveryCanBeChangedAndSavedFromDetails \
  -only-testing:$NAV/testLongSaveDisablesOnlySaveAndAllowsAnotherEdit \
  -only-testing:$NAV/testFailedSaveKeepsInputAndNavigationKeepsTheDraft
# The identical invocation was repeated with OUT-focus7 after the canceled launch.

ios/scripts/settings-tests.sh "$OUT-regression-red" HiBoss-UX-17 \
  -only-testing:$PREF/testAnEditDuringSavingRemainsUnsavedAfterTheResponse \
  -only-testing:$PREF/testQuietTimeUsesAModernUTCAnchorAndKeepsWallClockDigits
# Repeated with OUT-regression-red2 after the canceled launch.

ios/scripts/settings-tests.sh "$OUT-regression-green" HiBoss-UX-17 \
  -only-testing:$PREF/testAnEditDuringSavingRemainsUnsavedAfterTheResponse \
  -only-testing:$PREF/testQuietTimeUsesAModernUTCAnchorAndKeepsWallClockDigits \
  -only-testing:$NAV/testPriorityDeliveryCanBeChangedAndSavedFromDetails

ios/scripts/settings-tests.sh "$OUT-final-focused" HiBoss-UX-17 \
  -only-testing:$PREF -only-testing:$PERM \
  -only-testing:$NAV/testPriorityDeliveryCanBeChangedAndSavedFromDetails
```

Screenshot commands, from `ios/`:

```sh
SETTINGS_ONLY=1 scripts/ux-tour.sh "$OUT-after" HiBoss-UX-17
SETTINGS_ONLY=1 scripts/ux-tour.sh "$OUT-after" HiBoss-UX-17
SETTINGS_ONLY=1 scripts/ux-tour.sh "$OUT-final-tour" HiBoss-UX-17
SETTINGS_DELIVERY_ONLY=1 scripts/ux-tour.sh "$OUT-final-delivery" HiBoss-UX-17
```

The first capture had two Chinese harness failures because it expected the old
expiry-action translation. The second passed 4/0 in light and 4/0 in dark.
Large-text review then led to wrapping native delivery labels; the third capture
passed 4/0 in light and 4/0 in dark. Each complete matrix exports 144 screenshots.
The delivery-only capture passed 4/0 in each appearance and refreshed 16 images
after restoring the menu indicators.

The supplemental baseline used a temporary archive of `93685a0`, whose app
sources match `8bafbf1`; only a screenshot-test method was added. From its `ios/`:

```sh
"$XCODE" test -project HiBoss.xcodeproj -scheme HiBoss \
  -destination 'platform=iOS Simulator,name=HiBoss-UX-17' \
  -derivedDataPath "$OUT-baseline-intro-dd" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath "$OUT-baseline-intro.xcresult" \
  -only-testing:$TOUR/testMacIntroBaseline
```

Other checks, from the repo root:

```sh
python3 ios/scripts/i18n-audit.py
bash -n ios/scripts/ux-tour.sh ios/scripts/settings-tests.sh
git diff --check
security-guard artifact "$OUT-after/dd/Build/Products/Debug-iphonesimulator/HiBoss.app" \
  --repo "$PWD"
```

The localization audit, shell syntax check and diff check pass. All 60 added
localization keys have both English and Simplified Chinese values. The artifact
scan passed with zero findings. Final checks and full-suite counts follow below.

## Full-suite follow-up

The full suite on `3646f74a75a84df7199da5f2929a50e13606ce87` executed
167 unit tests and 69 UI tests. One UI test failed on both attempts before its
refresh action: `DecisionStateUITests.testFailedProgressRefreshKeepsPostsAndSaysTheyAreStale`.
Its initial Progress feed opened after the demo API's five-second success window
(`DemoProgressAPI.swift:10–16`). Starting that test on Progress using the existing
`HIBOSS_TAB` hook loads its initial data during that window. Its stale-banner,
retained-post and refresh assertions remain unchanged; production Progress code
and the demo API were not modified.

The same review found that permission feedback remained visible during phone
registration. `PushStatusStore.isWaitingForPermission` now ends that feedback
after authorization, while registration continues with its own status. Restoring
the previous predicate makes the new unit test fail.

Follow-up commands, from the repo root, using the aliases above:

```sh
ios/scripts/settings-tests.sh "$OUT-full" HiBoss-UX-17 \
  -skip-testing:$UI/UXTourUITests -retry-tests-on-failure -test-iterations 2
# Repeated as OUT-full-retry after the canceled startup, with the same HEAD.

ios/scripts/settings-tests.sh "$OUT-permission-red" HiBoss-UX-17 \
  -only-testing:$PERM/testPermissionWaitEndsBeforePhoneRegistrationFinishes \
  -only-testing:$UI/DecisionStateUITests/testFailedProgressRefreshKeepsPostsAndSaysTheyAreStale
# Repeated as OUT-permission-red2 after the canceled startup.

ios/scripts/settings-tests.sh "$OUT-permission-green" HiBoss-UX-17 \
  -only-testing:$PERM -only-testing:$PREF \
  -only-testing:$UI/DecisionStateUITests/testFailedProgressRefreshKeepsPostsAndSaysTheyAreStale
# Repeated as OUT-permission-green2 after the canceled startup.
```

## Final verification

The final full suite passed on
`c83d58cbc0ff31d41db4c903ea437307825079e9`: 237 passed, zero failed,
zero skipped and zero retries. The log records 168 unit tests and 69 UI tests.
Only `UXTourUITests` was excluded; the four Settings tour cases ran in this suite.
The known copy-link and media-viewer flakes passed on their first attempts.

Exact final command, from the repository root:

```sh
ios/scripts/settings-tests.sh /private/tmp/hiboss-settings-final-full HiBoss-UX-17 \
  -skip-testing:HiBossUITests/UXTourUITests \
  -retry-tests-on-failure -test-iterations 2
xcrun xcresulttool get test-results summary \
  --path /private/tmp/hiboss-settings-final-full.xcresult
python3 ios/scripts/i18n-audit.py
bash -n ios/scripts/ux-tour.sh ios/scripts/settings-tests.sh
git diff --check
security-guard artifact \
  /private/tmp/hiboss-settings-v2-dd/Build/Products/Debug-iphonesimulator/HiBoss.app \
  --repo "$PWD"
security-guard staged --repo "$PWD"
git status --porcelain
```

The result bundle is `/private/tmp/hiboss-settings-final-full.xcresult`.
Its `.head`, `.command` and `.log` siblings retain the tested commit and invocation.
Localization, shell syntax and diff checks passed; artifact and staged scans had
zero findings. The final documentation commit changes no executable source.
