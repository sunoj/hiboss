<!-- Per-screen specifications for the HiBoss web console: purpose, hierarchy, actions, states, roles.
     Part of docs/web-console-design.md. Components are defined in components.md. -->
# Web console screens

Each screen lists its content from top to bottom; that order is the hierarchy. "States" names only
what differs from the page states in [components](components.md). "Roles" names what a manager or
viewer loses; an admin has everything. Screens marked *mockup* are drawn in `docs/design-web/`.

## Today — `/` (*mockup: overview.html*)

**Purpose.** What needs me, what is running, what just arrived.

1. Header: date eyebrow, "Today", account button.
2. Status chips: "N need you", "N working", connection chip with freshness.
3. **Your call**: decision cards for every open decision, in the shared ranking of
   `docs/native-client-attention-model.md` (deadlines first). Options answer in place. The
   question links to the decision detail.
4. **Working now**: session rows with the current step and freshness; "All sessions" link.
5. **Delivered**: the latest results sent to the boss (agent to boss, not asks), newest first,
   up to ten; "All messages" link. Integration messages are included and labelled.

- **Actions.** Answer an option; open a decision, a session or a message.
- **States.** All clear replaces section 3 with the scene only under the all-clear rule. Offline
  keeps the last loaded content under a Signal banner, and options switch to "Checking…" 30 seconds
  after the stream drops. Before the open list first loads, the chip reads "Loading" and section 3
  shows two skeleton cards. Empty Working now and Delivered sections are omitted, not shown empty.
- **Roles.** Manager: granted agents only. Viewer: options are read-only text.

## Decision detail — `/messages/:id` for an open or resolved ask (*mockup: decision.html*)

**Purpose.** Everything needed to answer one decision, and the answer.

1. Back link to where the boss came from (Today, Messages or the session).
2. Provenance line: project · branch · agent · machine.
3. The question as the title.
4. Deadline banner (Signal) with the time left, the due time and the default sentence; or
   "No deadline" as plain text.
5. Facts: Changes, Risk, Undo, Evidence, when the message provides them; then the message's
   Markdown content.
6. Options, full width, with descriptions and images.
7. Custom answer field.
8. Context column: session facts with "Open session"; "Earlier in this session" (up to five
   messages, resolved decisions showing their outcome).

- **Actions.** Choose an option; send a custom answer; open the session; open an attachment.
- **States.** Resolved: items 4, 6 and 7 are replaced by the resolved banner; the facts stay.
  Answer rejected with 409: "No longer open", then the recorded outcome once fetched. Deadline
  passed locally: controls are disabled at once; the outcome appears when the server confirms it,
  and no default is claimed before that.
- **Roles.** Viewer: items 6 and 7 are replaced by the options as text and the view-only banner.

## Messages — `/messages`, `/messages/:id` (*mockup: messages.html*)

**Purpose.** The searchable record of everything sent and received.

List: search field (title and content); filter chips All, Needs you, From agents, From me,
Integrations; "More filters" (direction, status, priority, agent or session, Group by session);
the count line "Showing 50 of 248 · updated 6s ago"; message rows; "Load 50 more". Grouped by
session, each group has a header row with the session name and its message count.

Detail: provenance line and time; title; content (embed cards, Markdown, copy blocks);
attachments; options when the message is an ask (then the decision detail layout is used);
reactions (seen, working on it, done) and Forward; the reply field; a Details disclosure with
status and its times, priority, direction and mode, channel, expiry and the message ID.

- **Actions.** Search, filter, open, reply, react, forward to a channel, answer.
- **States.** Filtered-empty with "Clear filters". An integration message has no reply field and
  says why. Peer (agent to agent) messages are read-only and labelled "Between agents". A failed
  reply keeps the draft and shows the error under the field.
- **Roles.** Viewer: no reply field, reactions, Forward or options.

## Sessions — `/sessions`, `/sessions/:id` (*mockup: sessions.html*)

**Purpose.** Every agent run, by whether it needs the boss, and the conversation of one run.

List: search field (project, branch, agent, label); sections **Needs you**, **Working**, **Idle**
with counts; **Completed** in a closed disclosure. A session is in Needs you when it has an open
decision; the remaining buckets follow `SessionDirectory` in HibossKit, so the console and the
apps agree. Integration sessions appear in Idle with the Integration label.

Detail: header with "project · branch", a status badge, "agent · machine · started", and the live
step with freshness; the transcript, oldest first, with resolved decisions as banners, open
decisions answerable, attachments, and live panels as one row each; the reply field with its
target; "Leave a note instead", which leaves a session note that sends no notification.

- **Actions.** Open a session; answer; reply; leave a note; open the decision detail.
- **States.** No eligible reply target: the field is disabled with the reason ("This session has
  no message to reply to" or "Integration sessions cannot be replied to"). A completed session
  accepts notes only. Transcript load failure keeps the header and offers "Try again".
- **Roles.** Viewer: no reply field, notes or options.

## Agents — `/agents`, `/agents/:id` (*mockup: agents.html*)

**Purpose.** Which agents exist, how each authenticates, and how each sends.

Tabs: **Agents**, **Groups**, **Join requests** (with the pending count).

Agents list: search; rows with name, workflow role, key count, last seen, and badges for
"Admin capability" and "Integration". A Signal banner under the list names each agent with no
enabled channel.

Agent detail:

1. Identity: name, workflow role, ID, last seen, created; the Admin capability switch.
2. **Keys**: label, created, last used, created by, and Revoke; revoked keys stay listed and
   greyed. "Create key" takes a label and shows the key once.
3. **Sending defaults**: default priority, rate limit per minute, and priority routes (a priority
   mapped to a channel, for example Critical → Discord; add and remove). One Save button for the
   section, disabled until something changed.
4. **Channels**: one switch per configured channel, saved on change, with the note that
   credentials are set with the CLI.

Groups tab: one card per group with its name, owner agent, description and member count;
"Edit members" (add from a select, remove per member); "Broadcast" (group, priority, text, Send);
Delete with a confirm dialog; "Create group" (name, owner agent, description).

Join requests tab: pending requests with machine name, requested profiles and age; Approve and
Reject. Approval shows the result once; keys reach the machine through its own poll.

- **States.** Revoking the last live key of an agent: the dialog says the agent loses access until
  a new key is created. An integration has no keys; its Keys section lists webhook URLs by label
  with creation and last use, and states that they are managed with the CLI.
- **Roles.** Manager: sees granted agents; creates and revokes keys except for boss-linked or
  admin-capability agents, where the buttons are absent and a note explains it; no Admin
  capability switch; no Join requests tab. Viewer: read-only; no key, defaults, channel, group or
  broadcast controls.

## Delivery — `/delivery`

**Purpose.** Where the boss hears from agents.

Tabs: **Destinations**, **Rules**, **Providers** (admin only).

- **Destinations.** One row per destination: label, type (Telegram, Discord, Push device, Live
  client), route count, the Enabled switch, minimum priority, "Honour quiet hours", Test, Delete.
  "Add destination": provider, label, chat or channel ID, optional thread ID. When destination
  delivery is not on, a neutral banner says the settings take effect once it is enabled and Test
  is absent. Live clients cannot be tested and say so.
- **Rules.** The routing rules table: owner agent, channel, pattern (monospace), target agent,
  priority, enabled (read-only), Delete. Sortable by every column; default priority descending.
  "Add rule": owner agent, channel, pattern, target agent, priority. An invalid regular
  expression is reported on the field.
- **Providers.** Name and type per provider; "Add provider" with write-only credentials (bot
  token, optional Discord webhook URL) and the note that existing secrets are never displayed.

- **States.** No provider yet: non-admins read "An administrator must add a provider first."
- **Roles.** Manager: own destinations and rules for granted agents. Viewer: read-only with one
  banner, "You have view-only access."

## Projects — `/projects`

**Purpose.** The codebases sessions belong to.

Rows: display name, slug, aliases, session count, last seen, last post. Opening a row shows
"Display name" with Save and "Merge into" with a project select and Merge. The merge dialog
states that sessions, posts, aliases and routes move, that the target's profile is kept and that
it cannot be undone.

- **Roles.** Viewer: no rename or merge.

## People & access — `/access` (*mockup: access.html*)

**Purpose.** Who can see and answer for which agents.

1. Header with the one filled action, "Add a person".
2. **People**: name, role (a select), linked Telegram and Discord accounts, device count, Rotate
   token, Archive or Restore. Rotating shows the new token once and states that every existing
   token of that person stops working.
3. **Agent access**: a grid of people by agents; a checkbox grants or revokes at once. Admin rows
   are checked and disabled, with "Admins see every agent". Below 768 px each person becomes a
   card listing the agents.
4. **Add a person**: name, role, optional Telegram and Discord user IDs; the token is shown once.

- **States.** The last live admin cannot be demoted, archived or deleted: the controls are
  replaced by that sentence. A boss cannot archive itself. A failed grant returns the checkbox to
  its previous state with the error beside it.
- **Roles.** Admin only. Others get the Forbidden state and no navigation item.

## Devices — `/devices`

**Purpose.** The reader's own signed-in clients.

Rows: label, kind, "This browser" badge, created, last seen, push device and signing key
(Attached or None), Revoke. The dialog states that tokens and signing keys stop working and push
registrations are deleted. Revoked clients stay listed with their revocation date. "Add a device"
creates a pairing code shown with its five-minute expiry.

- **Roles.** Viewer: no "Add a device". This browser cannot be revoked here; Sign out does that.

## Audit — `/audit`

**Purpose.** Who did what.

Filters: actor type, action (with suggestions), page size, and a search within the loaded page;
Apply. Table: when (absolute, with the date), actor, action, resource, details. Pager with the
range and total. Below 768 px rows stack and details collapse behind a disclosure.

- **States.** "No audit entries" and "No rows match" are different messages.

## Server — `/server`

**Purpose.** Is this deployment healthy.

1. One status line: Healthy, Degraded or Unhealthy, with the time of the check and "Run checks
   again".
2. Checks as rows, each with its result in words: database, API and its latency, the signed-in
   boss and role, server time.
3. Channel health: one row per configured channel with its state and a hint when unhealthy.
4. Counts: active sessions, open decisions, channels.

- **States.** A failed check names the failing part; it never turns the whole page into an error.

## Connect — `/connect` (*mockup: connect.html*)

See [content and flows](content-and-flows.md#first-run-connect-to-this-server).

## More (phone and tablet) and the account menu

More lists Manage and Admin screens as grouped rows, then Devices, Language, Appearance and
Sign out. On desktop the last four are the account menu. Sign out asks for no confirmation,
revokes this browser's token on the server and returns to Connect.
