# macOS Dashboard home

The main window opens on Dashboard, combining the ranked decision queue with
the existing live Panels wall. Categories and sessions remain drill-down views
in the sidebar. The former standalone Panels destination is replaced by Dashboard.

## Composition and interaction

The visual direction is a calm native workspace: one page heading, restrained
section typography, and existing task cards as the primary interactive surfaces.
The content order is orientation, decisions, live task progress, and detail on demand.

At a content width of 980 points or more, decisions occupy a 300-point leading
column beside Panels. Smaller windows stack decisions before Panels. The default
window is 1320 by 820 points. The decision preview shows five entries in the wide
layout and two when stacked, with an explicit link to the complete ranked queue.

Decision and panel selection opens a native inspector. Decision opening uses a
short transition that respects Reduce Motion; the native inspector handles its
own reveal and adaptive layout. The wall stays in place while inspecting a task.
The existing decision options and reply composer are reused, including pending
submission protection, error messages, and retained message-specific drafts.
Resolved or expired decisions leave the queue and close their inspector.

MainView owns one PanelsModel across navigation changes. Panel subscriptions,
selection, filters, and form state survive visits to message categories or sessions.
The main refresh action refreshes both messages and Panels on Dashboard. Loading,
failure, and empty states remain independent, so a Panels failure does not hide
decisions. Demo decisions are explicitly labeled and cannot submit real answers
from the Dashboard inspector.

## Verification and deployment

`swift build --package-path macos --build-tests` succeeded, compiling the app and
all native test targets. A routing regression assertion covers the Dashboard's
ranked decision projection and excludes completed messages. Test compilation is
not test execution.

No local UI or E2E execution was performed: global instructions restrict those
checks to the authorized remote hosts, whose Linux environment cannot execute
SwiftUI. Interactive layout and inspector behavior still need macOS UI validation.

The release build was signed with the existing Developer ID identity and installed
at `/Applications/HiBoss Island.app` on 2026-09-08, retaining version 0.3.0 (12).
The previous application is backed up at
`/private/tmp/HiBoss-before-dashboard-f99fcabb70.app`. Signature verification and
the installed executable hash matched the packaged build. The installation receipt
is `/private/tmp/hiboss-dashboard-install.json`.

The matching production server and default CLI were subsequently upgraded to
lifecycle v2. All seven retained cards were adopted and read back successfully;
see [the rollout record](rollout-2026-09-08.md). Native UI/E2E execution remains
unverified under the remote-only testing rule.
