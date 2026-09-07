# Phase 0C — bundled React in WKWebView

Status: measured throwaway spike. Date: 2026-09-07. Host: macOS arm64, macOS 26.5 SDK.

This spike renders the untouched `panel-runtime/fixtures/metric-panel.json` and
`panel-runtime/fixtures/rollout-decision.json`. It does not edit or simplify either
fixture. The implementation lives under `spikes/panel-web/` and is not part of any root
workspace or shipped application target.

## Decision and bundle path

The spike uses `@json-render/core@0.20.0`, `@json-render/react@0.20.0`, React `19.2.3`,
ReactDOM `19.2.3`, Zod `4.3.6`, Vite `7.1.12`, and TypeScript `5.9.3`. The React peer
dependency is pinned to the exact compatible version in `web/package.json` and
`web/package-lock.json`.

The chosen SwiftPM-to-app-bundle path is implemented by
`spikes/panel-web/macos/scripts/build-app.sh`:

1. `npm ci --prefix web` installs from the checked-in lockfile.
2. `npm run build --prefix web` produces the self-contained Vite bundle.
3. The script copies `web/dist/` to `macos/Resources/Web/` and copies the two untouched
   fixtures to `macos/Resources/Fixtures/`.
4. SwiftPM declares `Resources` as a copied resource directory. `swift build` creates
   `PanelWebSpike_PanelWebSpike.bundle`.
5. The script copies that SwiftPM resource bundle into
   `Panel Web Spike.app/Contents/Resources/`, copies the executable and Info.plist, and
   ad-hoc signs the app.

This is the answer to how JavaScript enters a SwiftPM-built app: it is generated before
SwiftPM compilation, copied into a SwiftPM resource target, and shipped inside the
resource bundle nested in the app. There is no runtime download or CDN. The cost is a
Node/npm toolchain and a lockfile in the build environment, a build-order dependency,
generated resource copies that must stay synchronized with the Swift package, and a
rebuild/sign step whenever the registry or web bundle changes. The bundle is also a
separate WebKit process at runtime, so its memory is not represented only by the native
executable's footprint.

Build and type-check commands:

```sh
./spikes/panel-web/macos/scripts/build-app.sh
./spikes/panel-web/web/node_modules/.bin/tsc --noEmit
```

Both passed. The build uses `npm ci`; the only package-audit warning was one upstream
npm advisory in the dev dependency tree. It did not alter the pinned dependency set.

## Renderer boundary

The host sends `mount`, `applyTaskState`, and `requestStatus` as Codable Swift values to
`window.__hibossBridge.receive(message)` through `callAsyncJavaScript` arguments. It does
not interpolate JavaScript source. The view sends typed `draftChanged`, `actionRequested`,
`contentSizeChanged`, and `renderFailed` envelopes through the named WebKit message
handler. The native host owns the draft and accepts only `/form/strategy` and
`/form/trafficPercent` changes. `submitRequest` is logged as an intent; no submission is
implemented and no renderer-provided HTTP body is accepted.

The registry is bundled in the JavaScript asset. It implements the catalog families used
by the fixtures, including Stack, Metric, Select, NumberInput, and Button, plus bounded
placeholder implementations for the other initial catalog names. There is no eval,
runtime compilation, remote module loading, or direct component network access.

The document is loaded from `hiboss-panel://panel/` using `WKURLSchemeHandler`. The
configuration uses `.nonPersistent()` web storage, rejects navigation outside that
scheme and host, and serves only files below the generated `Web` resource directory.
The HTML content policy is `default-src 'self'`, `connect-src 'none'`, no objects, no
frames, and only same-origin scripts/styles.

This is defense-in-depth, not a security boundary. It does not protect against a WebKit
vulnerability, a compromised or buggy native bridge, malicious data already handed to the
renderer, a compromised host process, OS-level inspection, or mistakes in future registry
components. It also does not replace server-side action authorization or validate every
future catalog feature.

## Measurements

All timings below were collected from the built app produced by the build command above.
The host uses `DispatchTime.now().uptimeNanoseconds`; `footprint` reports macOS physical
footprint in MB. The panel was the sole active web view.

### Incremental memory per expanded panel

Instrumentation:

```sh
footprint -p <PanelWebSpike-pid>
footprint -p <com.apple.WebKit.WebContent-pid>
```

The host was launched with `HIBOSS_MOUNT_DELAY=5` so the baseline was sampled one second
after the app and WebKit page were initialized, immediately before the host sent `mount`.
The second sample was taken six seconds later, after `contentSizeChanged` and the first
interactive frame.

| Process | Before mount | Interactive | Delta |
| --- | ---: | ---: | ---: |
| Native `PanelWebSpike` | 35 MB | 34 MB | -1 MB |
| WebKit `WebContent` | 25 MB | 25 MB | 0 MB |
| Combined reported footprint | 60 MB | 59 MB | -1 MB |

The rounded negative host delta is measurement noise, not a memory saving. On this run the
incremental expanded-panel cost was approximately 0 MB after the already-running WebKit
page was initialized; the child process remained about 25 MB. A fresh app launch still
incurs the native/WebKit startup cost shown in the totals.

### Apply latency

Instrumentation: the host's `Run 200 applies` probe sent sequences 1–200 as typed
`applyTaskState` messages. Each update changed `/task/completed`. The renderer recorded
the applied sequence from a React render/layout cycle and posted `contentSizeChanged` from
the next `requestAnimationFrame`. The host stopped each sample on receipt of the matching
sequence and sorted 200 `DispatchTime` durations.

| Updates | p50 | p95 |
| ---: | ---: | ---: |
| 200 | 16.66 ms | 17.40 ms |

The displayed result came from the native probe log: `apply latency n=200 p50 16.66 ms
p95 17.40 ms`. This includes host-to-WebKit argument delivery, React/store work, layout,
one animation-frame boundary, and the return bridge message. It is not a JavaScript-only
render function benchmark.

### Cold mount

Instrumentation: the host records monotonic time immediately before sending `mount` and
stops at the first `contentSizeChanged` posted after the renderer's layout plus
`requestAnimationFrame`. The same app build rendered each fixture:

| Fixture | Cold mount to first interactive-frame signal |
| --- | ---: |
| `metric-panel.json` | 10.34 ms |
| `rollout-decision.json` | 37.17 ms |

The rollout value is higher because it mounts two form controls and a button rather than a
single metric. A WebKit page-load milestone is separate: unified WebKit logging reported
first meaningful paint at about 125 ms during the initial page load. The cold-mount values
above begin at the host `mount` request, after the static bundle page has loaded.

### Added size

Instrumentation:

```sh
find 'macos/dist/Panel Web Spike.app' -type f -print0 \
  | xargs -0 stat -f '%z %N'
```

Measured file sizes in the shipped app bundle:

| Component | Bytes |
| --- | ---: |
| Native Swift host executable | 317,904 |
| Bundled React/json-render JavaScript | 326,602 |
| CSS | 1,375 |
| HTML entry point | 850 |
| Two copied fixtures | 2,569 |
| App Info.plist | 793 |
| SwiftPM resource-bundle Info.plist | 793 |
| Code signature metadata | 4,578 |
| Sum of listed files | 655,464 |

The app occupied 664 KB by `du -sk` because filesystem allocation is block-sized. The
JavaScript bundle is the approach-specific payload measured here; the Swift executable is
the native shell and bridge required to host it. These are artifact sizes, not a claim that
all 317,904 native bytes would disappear from a production app with another renderer.

## Observed behavior

### Input focus

The rollout fixture rendered its real Select, NumberInput, and Submit button. They are
native HTML controls in DOM order. Tab and Shift-Tab follow that order, the CSS
`:focus-visible` rule produces a system highlight ring, and Command-A/Command-C retain
browser text-field behavior. Escape closes a native Select popup when one is open; the
spike does not invent an app-level Escape-to-cancel action. There is no custom focus
manager, so this is close to browser behavior rather than identical to every native
SwiftUI control.

### Text size

The page uses `-apple-system-body`, inherited `font: inherit`, rem sizing, and
`-webkit-text-size-adjust: 100%`. It follows the system font family/body baseline, but it
does not observe macOS Accessibility larger-text settings through a native bridge. Text
size is therefore not fully dynamic like a native SwiftUI view; this is a limitation.

### Appearance

The page declares `color-scheme: light dark`, uses Canvas/CanvasText/ButtonFace system
colors, and has a `prefers-color-scheme: dark` path. Light and dark surfaces therefore
come from the same system palette rather than hard-coded white/black panel surfaces. A
live light-to-dark switch was not automated in this run, so this is a code-backed pass,
not a recorded appearance-toggle benchmark. Native controls remain WebKit controls and
are expected to follow the same color scheme.

### VoiceOver

Visible labels wrap the form controls, so the real fixture's Strategy and Traffic
percentage fields have accessible names. The chart registry implementation exposes a
`role="img"` label and a visually hidden comma-separated values alternative. The metric
fixture itself has a visible label/value pair. There is no fixture validation-error state
and no dedicated validation-error component in this spike, so reachable validation errors
were not proven. VoiceOver was not run end-to-end; the semantics are present but should
not be treated as a production accessibility sign-off.

### Content height

The view posts `contentSizeChanged` with bounded `document.body.scrollHeight` in the
`requestAnimationFrame` after rendering. The native shell receives it and uses it as the
window's ideal panel height. This worked for both fixtures and is visible in the native
height status line. The value is a bounded web document height, not a native intrinsic
layout contract.

### Failure

Instrumentation:

```sh
webpid="$(pgrep -x com.apple.WebKit.WebContent | head -1)"
kill -KILL "$webpid"
screencapture -x /tmp/hiboss-panel-web-after-webprocess-kill.png
```

The native `PanelWebSpike` process remained alive and the WebKit view respawned/reloaded;
the host window and native fixture controls survived. A draft change is sent to the host
before it is used, and the host keeps it outside the web view, so a received draft
survives that renderer restart. The draft is only in memory in this spike: it does not
survive an app relaunch, and a keystroke lost before `draftChanged` is delivered is not
recoverable. Renderer-process recovery is observable, but there is no production-grade
error surface or explicit draft-reconciliation UI yet.

## Recommendation

Bundled React in WKWebView is viable when the catalog already matches a web team's needs:
the typed host boundary is straightforward, the bundle is small enough for this fixture
set, content height is measurable, and WebKit can recover its child process without taking
native navigation down.

The strongest argument against it is that this is not “a web view in a native app” for
free: the team must own a JavaScript build pipeline, a native bridge, WebKit-process
failure UX, and the accessibility/text-scaling gaps. The spike's clearest unresolved gap
is validation-error and VoiceOver parity; if form fidelity and platform accessibility are
the deciding criteria, the native catalog deserves the next comparison.
