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

## Verification

A routing regression assertion covers the Dashboard's ranked decision projection and
excludes completed messages. `PanelDashboardFlowTests` is the window-test class for the
Dashboard panel flow.
