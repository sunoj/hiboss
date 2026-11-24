<!-- Design for the HiBoss web console: goals, audiences, information architecture, layout and tokens.
     Components, per-screen specs and content rules are in docs/web-console-design/;
     static mockups are in docs/design-web/ (open index.html). -->
# Web console design

The web console (`web/`) becomes the browser client of HiBoss: the same product as the iOS and
macOS apps, with the administration the apps do not carry. It is served from the server's own
origin, so it is the first screen of a self-hosted deployment.

This design follows [the philosophy](philosophy.md) and [design v4](design-v4.md). Where a rule
below repeats a v4 rule, v4 is the source and the console must match the apps.

| Part | File |
|---|---|
| Goals, audiences, navigation, layout, tokens, what changed | this file |
| Component inventory and states | [components](web-console-design/components.md) |
| Every screen | [screens](web-console-design/screens.md) |
| Message rendering, first run, accessibility, motion, i18n | [content and flows](web-console-design/content-and-flows.md) |
| Mockups (HTML and CSS, light and dark, 375 px to desktop) | [`docs/design-web/`](design-web/index.html) |

The mockups are a precise picture, not code to port. `docs/design-web/tokens.css` is the token
source: it replaces the `--hb-*` tokens in `web/src/lib/design/tokens.css`, and components move
to the new names.

## Goals

1. **Answer first.** The first screen answers, in order: what needs me, what is running, what just
   arrived. A decision is answerable where it appears.
2. **One product.** A boss who knows the iPhone app recognises every screen: the same names
   (Today, Sessions, Your call, Working now, Delivered), the same colours with the same meanings,
   the same decision card, the same wording for defaults and outcomes.
3. **Administration without an admin tool.** Agents, keys, people, delivery and server health are
   reachable in two clicks and written in plain language, and stay out of the way of a boss who
   only answers.
4. **Honest state.** Loading, empty, offline, failed and forbidden are different states with
   different words. A count that is not loaded reads "Loading", never 0. Live values carry their age.
5. **One layout system** from 375 px to a wide desktop, in light and dark, in four languages.

## Principles

- **Colour has a job.** Signal means needs you, Live means working now, Settled means the boss's
  recorded answer or a healthy connection, Ink is the primary action. Nothing else is coloured.
  Priority, direction and delivery status are words, not colours.
- **One filled button.** Each decision card fills its first option with Ink, as in the apps.
  Outside decision cards a view has at most one filled button, its primary action; every other
  button is bordered.
- **Silence is not consent.** A timeout default is shown as a default, with the fixed sentence
  from v4, on a neutral fill. It never looks like the boss's answer.
- **Provenance on every item.** Project, branch, agent, and "Integration" for webhook senders.
- **The system's thing first.** Native form controls, the system font stack, the browser's focus
  order, links that are links. Custom drawing only for the decision card, the embed card and the
  all-clear scene.
- **Refresh never moves the layout.** After first load a refresh changes only the freshness label.

## Audiences and top tasks

Roles are defined in [business logic](business-logic.md). The console reads the role from
`/api/boss/me` and shows only what that role can do; the server remains the authority.

| Role | Who | Top tasks, in order |
|---|---|---|
| Admin | The self-hoster. Often the only boss. | Answer decisions. Read results. Follow sessions. Connect a machine: approve its join request, create a key. Add a person and grant agents. Set where notifications go. Check the server. |
| Manager | A teammate who answers for some agents. | Answer decisions for granted agents. Read results and sessions. Create or revoke keys of granted agents. Set own notification destinations. Manage own devices. |
| Viewer | Someone who watches. | Read decisions, results and sessions of granted agents. Nothing is answerable or editable; controls are absent, not disabled, except decision options, which are shown read-only so the question stays legible. |

## Information architecture

Three levels, most used first.

| Level | Items | Shown to |
|---|---|---|
| Primary | **Today** (open-decision count), **Sessions**, **Messages** | Everyone |
| Manage | **Agents** (agents, keys, channels, groups, join requests), **Delivery** (destinations, routing rules, providers), **Projects** | Everyone; write controls by role |
| System | **People & access**, **Audit**, **Server** | People & access: admin only. Audit and Server: everyone; the server scopes a non-admin's audit rows to its own actions and its granted agents. |
| Account menu | Signed-in boss and role, **Devices**, language, appearance, Sign out | Everyone |

Why this order: decisions are why a boss opens HiBoss, sessions are where the work is, and
Messages is the searchable record. Everything in Manage and System is occasional.

### Routes

| Route | Screen | Today's route |
|---|---|---|
| `/` | Today | `/` (Dashboard) |
| `/messages`, `/messages/:id` | Messages and one message. An open ask renders as the decision detail. | `/messages` and its drawer |
| `/sessions`, `/sessions/:id` | Sessions and one session transcript | `/sessions` and its drawer |
| `/agents`, `/agents/:id` | Agents; tabs Agents, Groups, Join requests | `/agents`, `/groups`, `/channels` |
| `/delivery` | Tabs Destinations, Rules, Providers | `/notifications`, `/routing` |
| `/projects` | Projects | `/projects` |
| `/access` | People & access | `/bosses` |
| `/devices` | Devices (from the account menu) | `/devices` |
| `/audit` | Audit | `/audit` |
| `/server` | Server | `/system` |
| `/connect` | Connect | `/connect` |

Old paths (`/groups`, `/channels`, `/notifications`, `/routing`, `/bosses`, `/system`) redirect to
the new screen and tab. Every detail has its own URL, so a row can be opened in a new tab, shared
and reached by the browser's Back button; today's drawers have none of these.

## Layout system

| Class | Width | Navigation | Content |
|---|---|---|---|
| Phone | 375–767 px | Bottom tab bar: Today, Sessions, Messages, More | One column, 16 px side margin. A list and its detail are separate views. |
| Tablet | 768–1023 px | Bottom tab bar | List and detail side by side. |
| Desktop | ≥ 1024 px | Sidebar 244 px, sticky, full height | Content padded 24 px top, 32 px sides. |

- **Reading width.** Single-column screens (Today, a decision's main column, forms) are at most
  900 px wide and centred. Split screens and tables are at most 1200 px.
- **Split view** (Messages, Sessions, Agents): the list column is 36 % of the content, between
  260 and 360 px; the detail column takes the rest (about 440 px at 768 and at 1024 px). Below 768 px the detail replaces the list and shows a back link. The list keeps
  its scroll position and selection when the boss returns.
- **Decision detail** adds a 300 px context column (session facts, earlier in this session) when
  the content area is wider than 760 px; otherwise the context follows the decision.
- **More** on the tab bar opens a page listing Manage, System and the account items as grouped rows.
- **Tables** respond to their container, not the viewport: in a container narrower than 600 px
  each row becomes a labelled stack (`.table.stack` in the mockups), so a table inside a split
  view's detail stacks on a tablet too. No screen scrolls sideways at 375 px, except a code block
  or a Markdown table inside its own scroll area.
- **Targets.** 44 px minimum for anything tappable on touch layouts; 32 px minimum for dense
  desktop actions with a pointer.
- **Sticky parts.** The sidebar, the tab bar, and the reply field of a session on desktop. Nothing
  else sticks.
- The page respects `env(safe-area-inset-bottom)` under the tab bar.

## Design tokens

Tokens are CSS custom properties in [`tokens.css`](design-web/tokens.css). Components use tokens
only; a hex value in a component is a defect. The one exception is an embed card's edge colour,
which is data from the sender.

### Colour roles

| Token | Light | Dark | Native v4 name | Use (only this) |
|---|---|---|---|---|
| `--ink` | #111317 | #F2F3F5 | `Ink` | Primary text; fill of the primary button |
| `--on-ink` | #FFFFFF | #111317 | none (web) | Text on an Ink fill |
| `--signal` | #C2410C | #F97316 | `Signal` | Needs you: deadlines, open counts, Needs you dots |
| `--live` | #1D5FD8 | #7FB0FF | `Live` | Working now, links, focus ring, provenance badges |
| `--settled` | #15803D | #4ADE80 | `Settled` | The boss's recorded answer; a healthy connection; a switch that is on |
| `--ground` | #F2F3F5 | #0E0F12 | `Ground` | Page background |
| `--surface` | #FFFFFF | #1A1C21 | `Surface` | Cards, grouped rows, fields |
| `--text-2` | #4A505A | #B4B9C2 | `SecondaryText` | Context, meta, field labels |
| `--text-3` | #5F6570 | #9EA5AF | `TertiaryText` | Timestamps, footnotes, placeholders |
| `--hairline` | #E4E6EA | #2A2D34 | `Hairline` | Separators |
| `--signal-soft` | #FFF1E8 | #3A2414 | `SignalSoft` | Fill behind Signal text |
| `--live-soft` | #EAF1FD | #18243A | `LiveSoft` | Fill behind Live text; the selected list row |
| `--settled-soft` | #EEF6F0 | #13301F | `SettledSoft` | Fill behind Settled text |
| `--surface-2` | #F7F8F9 | #22252B | none (web) | Hovered row, code and copy block fill, the boss's own message |
| `--neutral-soft` | #ECEEF1 | #262930 | none (web) | Neutral badge and banner fill, selected navigation item |
| `--border` | #D5D8DD | #3A3E47 | none (web) | Outline of bordered buttons |
| `--field-border` | #7C828D | #7A808B | none (web) | Outline of inputs, selects and switches (3:1 against Surface) |
| `--danger` | #B42318 | #FF8A80 | system red | Destructive action labels and error text |
| `--danger-soft` | #FEECEB | #3A1A18 | none (web) | Fill behind error text |

The current console's priority, status, direction and session-state colours (17 tokens) are
removed. Brand colours (Sky, Lagoon, Sand, Palm) appear only inside the island scenes.

Theme: light by default; dark when the system asks for it; `data-theme="light"` or `"dark"` on
`<html>` pins one. The appearance control in the account menu has three values: System, Light, Dark.

### Type

System font stack with CJK fallbacks, no web fonts. Sizes are in `rem`, so the browser's text size
setting scales the whole console; layouts must hold at 200 %.

| Token | Size / line | Weight | Native style | Use |
|---|---|---|---|---|
| `--t-large` | 30 / 36 px | 700 | `.largeTitle` | Screen title |
| `--t-title` | 22 / 28 px | 700 | `.title2` | Detail title: a decision's question, a message, a session |
| `--t-headline` | 17 / 22 px | 600 | `.headline` | A question on a card; dialog and empty-state titles |
| `--t-body` | 15 / 22 px | 400 | `.subheadline` | Body, message content |
| `--t-callout` | 14 / 20 px | 400 or 600 | `.callout` | Rows, buttons, table cells |
| `--t-footnote` | 13 / 18 px | 400 | `.footnote` | Section headers, meta, help text |
| `--t-caption` | 12 / 16 px | 400 or 600 | `.caption` | Badges, card footers, tab bar labels |
| `--t-mono` | 13 / 20 px | 400 | monospaced | Code, copy blocks, IDs, keys |

Input text is 16 px on every layout, so iOS Safari does not zoom on focus. Message content is at
most 68 characters wide.

### Space, radius, size, elevation

| Group | Tokens | Native source |
|---|---|---|
| Space | `--s-1`…`--s-7` = 4, 8, 12, 16, 20, 24, 32 px. Card padding and the phone side margin are both 16. | `Space` |
| Radius | `--r-s` 8 (tiles, tags), `--r-m` 12 (buttons, fields, banners, embed and copy blocks), `--r-l` 16 (cards, grouped rows), `--r-pill` (chips, badges, switches) | `Radius` |
| Tile | 20 inline, 28 beside a card's provenance line, 40 leading a row | `AvatarSize` |
| Elevation 0 | Cards and rows: no shadow and no border; Surface on Ground is the separation | grouped list |
| Elevation 1 | Menus, dialogs, toasts: `--overlay` shadow plus a hairline; a dialog adds the `--scrim` | sheet, popover |

## What was removed, merged or demoted

| Today | Change | Why |
|---|---|---|
| Dashboard KPI cards (active sessions, pending decisions, blocking pending, unread 1 h) | Removed. Status chips "N need you", "N working" and the connection chip replace them. | Four numbers above the fold delayed the decisions they counted. |
| Priority distribution chart, session status bars | Removed | Retrospective counts answer none of the three questions. |
| Channel health on the dashboard | Moved to Server | It is a setup check, not daily state. |
| Recent messages (latest 10, every direction) | Replaced by Delivered: results sent to the boss | Peer traffic and the boss's own replies are not news to the boss. They stay in Messages. |
| Sessions Kanban, five status columns | Replaced by one list grouped Needs you, Working, Idle, Completed | Five columns do not fit a phone, and "blocked" or "waiting" did not say whether the boss must act. The grouping matches the apps. |
| Session drawer with a disabled "Send a command" | Replaced by the session transcript with a working reply field and notes | A permanently disabled control is noise. |
| Message, session and agent drawers | Replaced by addressable detail views | Drawers had no URL, covered the list on tablets and trapped focus. |
| Message filter form (five fields, always open) | Search and five filter chips; the fields move behind "More filters" | Most visits use one filter. |
| Flat or by-session toggle | Kept as "Group by session" inside More filters | Same function, less chrome. |
| Raw message ID in the drawer header; status, direction and mode badges on every row | Demoted to a Details disclosure on the message | Needed for support, not for reading. |
| `/groups` | Merged into Agents as a tab | A group is a set of agents; its only actions are members and broadcast. |
| `/channels` | Merged into the agent's detail, as its Channels section | A channel switch belongs to one agent. The list keeps the "no enabled channel" warning. |
| `/notifications` and `/routing` | Merged into Delivery | Both answer "where does a message go". |
| `/bosses` "Bosses & Access" | Renamed People & access | "Boss" is the product's word for the reader, who is one of the people listed. |
| `/system` "System / Doctor" | Renamed Server; the toast after a check is removed | The result is on the page. |
| `/devices` in the sidebar | Moved to the account menu | It lists the reader's own sign-ins. |
| Sidebar of twelve equal items | Three primary items and two labelled groups | The primary tasks were one third of an undifferentiated list. |
| Session ID, branch and working directory as drawer rows | Demoted to a Details disclosure in the session header | Needed to find a session on disk, not to follow it. |
| Top bar (connection light, server URL, boss name, language, Sign out) | Removed. Connection and server sit in the sidebar footer; the rest is the account menu. | A permanent bar spent 48 px on rarely used controls. |
| Page subtitles such as "Messages — full stream, filters, session grouping, detail drawer" | Removed | They described the interface, not the content. |
| Dark-first palette with a blue accent; IBM Plex | Replaced by v4 roles, light and dark equal, system fonts | The console must read as the same product as the apps, and loads no web fonts. |
| `window.confirm` dialogs and success toasts for every action | Confirm dialog component for destructive actions only; results shown in place | A system dialog cannot be styled or translated consistently, and a toast is missed by screen readers and gone before it is read. |

Nothing the current console can do is lost: every action above keeps a place in
[screens](web-console-design/screens.md).

## Not in this design

Box, the Progress feed and the live panel wall stay in the apps. In a session transcript a live
panel appears as one row with its title, state and freshness; it is not drawn. An intake
questionnaire appears as a row stating that it is answered in the apps.

## Server capabilities the console starts using

The current console calls none of these except agent keys. They are server capabilities used by
the apps or the CLI; the implementer confirms each request shape against `docs/reference/` before
building, and a capability the deployed server lacks degrades as the last column says. Embed
cards and integrations come with the Discord-compatible webhook endpoint; a server without it
sends no `rich_content` and has no integration agents.

| Capability | Used for | If unavailable |
|---|---|---|
| The open required-input list and its stream | The answerable rule: which decisions are open | Options stay disabled as "Checking…"; no screen claims all clear |
| Pairing-code redemption (`POST /api/pairing/redeem`) | Connect with a pairing code | The token path remains |
| Pairing-code creation | Devices › Add a device | The action is absent |
| Revoking the caller's own token | Sign out | The token is deleted from the browser only |
| Session events and stream | Session transcript and live step | The transcript shows loaded messages with their load time |
| Session notes | "Leave a note" in a session | The action is absent |
| Join-request list, approve and reject | Agents › Join requests | The tab is absent |
| A reachability check that needs no token | The first line of Connect | The line is omitted; the first signed-in call reports failure |
| An agent's admin capability, read and write | Agents: the badge and the switch | Both are absent |
| An agent's kind (agent or integration) | The Integration badge; hiding the reply field | The reply's 409 is shown as "Replies are off for this sender" |
| Boss archive, restore and role change | People & access | The row shows the role as text |
| Embed cards (`metadata.rich_content`) and integrations | Embed card rendering, the Integration badge | `metadata.content` is rendered as Markdown |
