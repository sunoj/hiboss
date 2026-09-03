# iOS Client — Native Design Contract

The macOS client has `docs/macos-design-v2.md` because a palette-driven first
attempt once shipped something that read as a web page in a window. iOS never
got the same document, and the gap showed the first time an agent rebuilt the
home screen: the foundation was already correct and the new code walked around
it. This file locks in what is right and names what went wrong.

## 0. The rule that overrides everything

**Use the system's thing.** A system control, a system colour role, a system
font style. Reach for a custom drawing only where the system has nothing to
offer and the drawing carries meaning a control cannot.

An iPhone user has thousands of hours of muscle memory for how iOS behaves.
Every place this app invents its own version of something the platform already
does, it spends that memory for nothing.

## 1. Colour — already correct, keep it that way

`ios/App/Theme/Palette.swift` maps every token onto a semantic UIKit role:
`.label`, `.secondaryLabel`, `.systemGroupedBackground`,
`.secondarySystemGroupedBackground`, `.separator`. That is exactly right. Those
roles follow dark mode, Increase Contrast and Smart Invert for free.

- **Views never name a colour.** They use `Theme.ink`, `Theme.surface`,
  `Theme.positive`. No `Color(red:green:blue:)`, no hex, no `Color.gray`.
- **New tokens map to a system role**, not to a value someone picked. If no
  role fits, that is a signal the design wants something the platform does not,
  and the design is what should change.
- Green and red carry meaning (settled / stopped). They are the only tokens
  allowed to be decorative-looking, and only in that meaning.

## 2. Type — already correct, and this is where it broke

`ios/App/Theme/Typography.swift` builds every token on a semantic style:
`Font.title2`, `Font.callout`, `Font.caption`. Those scale with Dynamic Type.

**`.font(.system(size:))` is banned in views.** It is a fixed point size: it
ignores the user's text-size setting, and for a boss who has enlarged type
because they are reading a decision on a phone at arm's length, it silently
opts them out.

This is not hypothetical — the rebuilt attention home shipped
`Image(systemName: "checkmark.circle.fill").font(.system(size: 48))` in its
empty state on 2026-09-03. Size a symbol with a text style
(`.font(.largeTitle)`, `.imageScale(.large)`) or with
`.symbolRenderingMode` and a token, never with a number.

Add a token when a style is missing. Do not inline a size.

**The widget target is exempt.** `ios/Widgets` is a compact surface the system
scales itself, with its own layout constraints and no Dynamic Type ramp to
follow; it keeps its fixed sizes deliberately. The ban applies to `ios/App`.
When the sweep of 2026-09-03 cleared `ios/App` it left 17 fixed sizes in the
widget on purpose — that is a decision, not an oversight.

## 3. The fold is the scarcest thing on the phone

A Mac window can afford a heading that says where you are. A phone cannot.

- **The top of the screen belongs to the thing the boss came for.** Before the
  attention rebuild, the iOS home spent its entire first screen on a seven-column
  activity heatmap and three percentage deltas, and pushed the decisions that
  needed the boss to start exactly at the tab bar.
- **Do not stack two headings that say the same thing.** A navigation title
  reading "Home" above a content heading reading "Needs you now" costs ~15% of
  the viewport to say nothing. Keep the one that states the job.
- Retrospective content — history, counts, trends — is never above
  present-tense content.

## 4. Motion and craft

The app owns one bespoke drawing: `AllClearIslandView` — a Canvas scene with a
motion phase and its own colour set under `Assets.xcassets/AllClearIsland`. It
exists because "nothing needs you" is the answer the boss opens the app hoping
for, and that answer deserves to feel settled rather than merely empty.

- **An empty state that the product wants people to reach is worth drawing.** A
  system checkmark is the right default for an incidental empty list and the
  wrong one for this. When a surface's empty state is the all-clear state, it
  gets the island.
- Any motion respects `accessibilityReduceMotion`. `AllClearIslandMotion`
  already takes it as a parameter; new motion does the same or does not ship.
- Craft is not decoration to be dropped in a refactor. A rebuild that removes
  the surface an illustration lived on must say where the illustration went —
  the island lost its home when the Inbox tab was merged away, and nobody
  noticed until the boss asked.

## 5. Reach and touch

- Anything tappable is at least 44×44 pt, including a chevron.
- The primary action of a screen sits within thumb reach on a 6.1" phone —
  lower half, not pinned under the navigation bar.
- Decisions are actionable from the list. Making the boss open a detail screen
  to answer a two-option question is a step the phone cannot spare.

## 6. The Dynamic Island and the app must agree

Live Activity, notification and app all present the same work. If the Live
Activity shows one decision first and the app lists a different one first, the
boss stops trusting both. The ranking in `docs/native-client-attention-model.md`
is the single source; every surface sorts by it. macOS has
`AttentionIslandAgreementTests` for exactly this — iOS needs the equivalent
before it grows a second ranked surface.

## 7. Verification

Reading the diff is not verification. For any UI change:

```sh
xcodebuild -project HiBoss.xcodeproj -scheme HiBoss -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd> build
xcrun simctl install booted <dd>/Build/Products/Debug-iphonesimulator/HiBoss.app
SIMCTL_CHILD_HIBOSS_DEMO=1 xcrun simctl launch booted ai.hiboss.app
xcrun simctl io booted screenshot shot.png
```

Then **look at the image**. Simulator names drift with Xcode; an invalid
`-destination` prints the valid list rather than failing usefully.

A screenshot taken immediately after `simctl launch` can capture a blank window
before first render. Wait for content — a suspiciously small PNG is the tell.

Screenshot the empty state too. It is the common case and it is the one nobody
renders.

## 8. Status

Written 2026-09-03, during the attention-model rebuild. The colour and type
foundations predate it and are sound; sections 3 through 6 are the rules that
had no home before and were each violated at least once in that rebuild.
