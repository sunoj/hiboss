# Native control follow-up — 2026-09-11

## Multi-selection refresh

The production questionnaire `b1a76841-ee7a-40eb-a192-3ac248d28ac1`
already contained the accepted choices `draft` and `media` when the user reported
that checkboxes could not be selected. The answer write succeeded; its visible
selection feedback was unreliable.

`PanelRenderer` declared `@ObservedObject` on a plain renderer struct. Its nested
rendering closures were not independently installed SwiftUI views, so stable
`ForEach` children could retain their old appearance after the store changed.
The shared renderer now conforms to `View`, and each child is an observing view.
Multi-selection captures the current selection during rendering, giving option
rows an explicit changed value to display. Writes still merge with the latest
store selection so choosing a second option preserves the first.

The macOS panel detail, iOS panel detail, and shared questionnaire editor now use
this view directly. Other bound controls and displayed task values also use this
observation path.

## Image preview

The macOS image preview uses a popover with native outside-click dismissal.
Its background, Close button, and Escape key also dismiss it. Clicking the image
itself preserves the preview. Answered history messages retain their thumbnails
and image viewers while answer buttons remain disabled.

## Demo lifecycle

The original A/B message and questionnaire were independent interactions. An
accepted answer resolves its questionnaire; it does not complete the producer's
task. The demo producer had stopped without completing its card.

The original card `panel_5ad233ac-454c-4db8-a15b-40669034fddc` was explicitly
completed with immediate dismissal. Its accepted answer was acknowledged and
preserved. A first completion request incorrectly used the checkpoint epoch as
the live lease epoch and received `fenced_epoch`. Readback confirmed the lease had
been released; completion succeeded with a null live epoch and the original
checkpoint cursor.

A new bounded verification execution uses panel
`panel_252c2a0a-1969-47c8-80d4-2fe0946c2c5c` and questionnaire
`55daaa2b-6814-410b-812e-5776afb36d99`. It is paused while waiting for human input.
Its tracked CLI watcher completes and immediately dismisses that card after an
accepted answer. Unanswered input expires after 15 minutes and the watcher cancels
the demo. This is demo orchestration, not a global policy that ends ongoing work
whenever any questionnaire receives an answer.

## Validation and installation

- Remote questionnaire HTTP E2E: 20 passed across four files on
  `the Linux build box`, workspace `/tmp/hiboss-rich-media.GO2jIj`.
- The added regression verifies multi-selection validation, accepted-answer
  discovery, immediate card dismissal, and preserved immutable answers.
- Shared questionnaire model, presentation, and API unit tests: 14 passed locally
  with stubs, no UI or network execution.
- macOS Release and unsigned generic iPhoneOS builds passed.
- Signed macOS bundle passed deep/strict verification and retains the previous
  installation's designated requirement.
- Installed and launched `/Applications/HiBoss Island.app`, process ID `72032`.
- Executable SHA-256:
  `095a2efbbc174cfceec7f1b0d06315b83366b57bbf6e695a86da0776b93a2313`.
- Previous bundle:
  `~/Library/Application Support/HiBoss/Backups/HiBoss Island.before-controls-20260911.app`.
- Build, test, publication, completion, and installation evidence is under
  `output/native-ui-demo/`. The unsigned iOS app is in its `iOS/HiBoss.app` folder.

The user requested the local replacement and launch. No automated local native UI
interaction check was run for these fixes. The authorized remote host is Linux
and cannot execute SwiftUI. Remote HTTP E2E and local model tests do not establish
native visual confirmation.

## User verification

The user subsequently confirmed the corrected multi-selection interaction worked
on the installed Mac build. Server readback confirmed accepted choices `live` and
`media`, with delivery acknowledged. The demo watcher automatically completed the
card at `2026-09-11T10:29:14.272Z` with immediate dismissal.

Evidence: `output/native-ui-demo/recheck/request-final.json`, `panel-final.json`,
and `watcher.log`. Separate visual confirmation of image-preview dismissal and
iOS device interaction is still outstanding.
