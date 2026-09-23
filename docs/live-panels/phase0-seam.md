<!--
Phase 0F seam evidence report for the mixed native form and web display leaf.
Exports: six observations, repeatable commands, captured stdout, and screenshot references.
Dependencies: spikes/panel-seam, panel-runtime validator, macOS AppKit/WebKit.
-->

# Phase 0F seam evidence

Date: 2026-09-07. The harness is under `spikes/panel-seam/`; it copies the
`mixed-panel.json` fixture into the app bundle at build time. The fixture passed
`validatePanelSpec` with declared paths `/form/strategy` and
`/form/trafficPercent`.

The native tree is `Select → LineChart leaf → NumberInput → Button`. The web
bundle contains only the LineChart display leaf. The window is deliberately short
enough that the native `ScrollView` owns a taller document.

## Observed answers

1. **Scroll ownership — physical trackpad not observed.** The repeatable probe
   posted a synthetic precise scroll event at the chart's screen coordinates.
   Neither the chart's WebKit scroll view nor the native page scroll view moved:
   `HostingScrollView=0` before and after. The automated result was **nothing**.
   A person must repeat this with a real trackpad to turn the proxy observation into
   a physical-input observation.

2. **Height negotiation — settled.** The web leaf reported heights of
   `266, 386, 176` points: the initial size, then a `360)-point chart, then a
   `150)-point chart plus document padding. The native slot did not oscillate or
   clip; the final callback was the lower requested state.

3. **Keyboard traversal — web leaf skipped; semantic native order not observed.**
   The probe's forward and backward key-view walks never returned `web-leaf`
   after the leaf was made non-first-responder. AppKit exposed the same shared
   field-editor responder repeatedly, so the raw order was
   `native:80>native:80>native:80>native:80>native:80) in both directions.
   That is not enough evidence to name Select, NumberInput, and Button in semantic
   order. A person must press Tab and Shift-Tab while watching focus rings; the
   focus rings were not observed.

4. **Appearance — the leaf follows the system, corrected by the orchestrator.**
   The probe reported this as "stranded light". That finding was wrong, and the
   cause was the method, not the app: `defaults write -g AppleInterfaceStyle Dark`
   changes the stored value without telling running or newly launched apps to
   re-resolve their appearance, so nothing switched and the probe honestly reported
   that nothing reached the app.

   Re-tested with `osascript -e 'tell app "System Events" to tell appearance
   preferences to set dark mode to true'`. Both the spike and the shipped
   HiBoss Island window turned dark, and **the web leaf turned dark with them** —
   dark chart background, adjusted series colour, no stranded light rectangle.
   Evidence was captured by the orchestrator; the private terminal screenshot
   was removed during public-release preparation.

   A control run mattered here. Under the wrong method the *shipped* app also stayed
   light, which is what showed the defect was in the measurement rather than in
   either app. Use the System Events route for any future appearance check.

5. **VoiceOver — not observed.** VoiceOver was not run. No claim is made about
   the accessibility tree across the boundary. A person needs to enable VoiceOver
   and traverse forward and backward through the live form and chart.

6. **Renderer death under a live draft — native state survived.** The targeted
   `com.apple.WebKit.WebContent` process was killed with SIGKILL. The native
   draft remained `strategy=full trafficPercent=80`; the native window remained
   visible; and the web slot showed `Web content process terminated`.

## Captured stdout

This is the stdout block from `spikes/panel-seam/scripts/run-probe.sh`:

```text
appearance_state=light_restored
renderer_kill_pid=2674
draft_before_kill=strategy=full trafficPercent=80
appearance_native_initial=NSAppearanceNameAqua
voiceover=not observed
height_callbacks=266,386,176
height_result=settled
tab_forward=native:80>native:80>native:80>native:80>native:80
tab_backward=native:80>native:80>native:80>native:80>native:80
focus_ring=not observed (requires a person watching the window)
probe_ready=1
scroll_synthetic_over_chart=nothing
scroll_offsets_before=["HostingScrollView=0"]
scroll_offsets_after=["HostingScrollView=0"]
renderer_failure=Web content process terminated
native_draft_after_kill=strategy=full trafficPercent=80
window_visible_after_renderer_death=true
leaf_slot=Web content process terminated
```

The same run printed the screenshot paths before that block:

```text
<worktree>/feat/panels-seam-spike/spikes/panel-seam/evidence/light.png
appearance_state=light screenshot=<worktree>/feat/panels-seam-spike/spikes/panel-seam/evidence/light.png
<worktree>/feat/panels-seam-spike/spikes/panel-seam/evidence/dark.png
appearance_state=dark screenshot=<worktree>/feat/panels-seam-spike/spikes/panel-seam/evidence/dark.png
```

Build and probe commands:

```text
./spikes/panel-seam/scripts/build-app.sh
./spikes/panel-seam/scripts/run-probe.sh
```

## Decision boundary

Nothing observed here invalidates the split's native draft/navigation ownership,
display-only restriction, or height settling. The appearance result is an open
seam defect: this harness did not propagate the requested global appearance change
to an already mounted app.

The one observation that would make me abandon the split is renderer death taking
the native draft or navigation with it. That is the boundary's safety invariant;
this run showed the opposite.
