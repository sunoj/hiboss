# Stable Surfaces — Loading and Refresh Without Layout Jumps

Applies to every native surface: iOS app, iOS widgets and Live Activity, macOS windows and
the Island. It extends the per-surface rules in `docs/ios-intermediate-states.md`; where the
two overlap, this document is the cross-platform statement and that one the iOS inventory.

## The rule

**Once a surface has shown content, a refresh never changes its layout.** Only a small
status element changes: a status line, a toolbar progress indicator, or a "Updating…" /
"Updated 37 s ago" label. Content, section structure, empty states, illustrations and
control enablement stay as they were until the new result arrives, and then change once,
directly to that result.

## What follows from it

1. **Placeholders are for absent content only.** A full-area spinner, redacted rows or a
   "Loading…" page appear on the first load, when nothing is cached. A refresh, a
   reconnect, a foreground reload, a filter change with cached results, or a background
   sync never brings them back.
2. **Loading is not a health state.** "Request in flight" must not be modelled as the same
   value as "no data yet". Keep them separate (for example `hasLoaded` plus `isRefreshing`)
   so a refresh cannot reach code that renders the first-load layout.
3. **Empty and all-clear states are results, not defaults.** "Nothing needs you", "No
   items" and similar appear only after a completed fetch says so, and stay visible while
   the next refresh runs. They never flash between refreshes.
4. **Controls keep their state during refresh.** Buttons, choices and text input do not
   disable or switch to "checking" because a background read is in flight. Only the action
   being submitted shows progress.
5. **Delay progress UI by 300 ms.** A fast refresh shows nothing at all.
6. **Reserve geometry.** Images, thumbnails, avatars and media keep their final size while
   loading; progress appears inside the reserved box. Lists keep row heights; inserting the
   result must not push the viewport.
7. **Failures over cached content are annotations.** A failed refresh keeps the content and
   adds a compact stale/offline line with Retry; it never replaces the content with an
   error page.
8. **One result, one change.** Apply a refresh result in a single update. Do not clear a
   collection and then refill it, and do not publish intermediate partial states to the view.

## Exception: the account boundary

The rule covers refreshes, not a change of who the content belongs to. Two events clear account
content on purpose, on iOS and macOS. Both go through `HibossKit` `AccountAuthorization`:

- **Rejection.** An authenticated 401 on a boss-token request calls `reject(_:)`.
  Observers drop cached content, reply drafts, questionnaire editors and saved drafts, panel
  state and device requests. Requests stay refused until an accepted reconnect, which
  includes a same-account reconnect. A 403 is not a rejection: the credential is valid but
  lacks permission for that one action, so the surface shows a permission message and the
  account and its content stay as they are.
- **Account change.** A different `ConnectionConfig` calls `connect(_:)`. It purges the
  previous account's persisted drafts and advances the identity generation, so in-flight
  results from the previous account are discarded.

A model that mirrors the boundary's refusal derives it from `AccountAuthorization` in its
`reset()`. It never writes a default, so a later reset cannot reopen a rejected account.

## Verification

- Every list or dashboard surface has a test that refreshes with cached content and asserts
  that the content, the empty/all-clear state and the enabled controls are unchanged while
  the refresh is in flight, and that only the status element differs.
- Screenshots of a surface mid-refresh and after refresh show the same layout.
