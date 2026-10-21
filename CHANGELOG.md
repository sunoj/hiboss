# Changelog

All notable user-visible changes. Earlier CLI versions are listed in the
[version history](docs/reference/roadmap-history.md).

## 1.0.0 — unreleased

The first public release of HiBoss: a self-hosted server, the `hiboss` CLI, the iPhone
and Mac apps, the web console and the Claude Code MCP server.

### Server and setup

- One Cloudflare Worker with D1, R2 and Durable Objects; migrations apply on deploy.
- First install on an empty server: `hiboss setup --bootstrap-secret … --boss-name …`
  creates the admin boss, prints a pairing link and QR code, and enrols the machine
  after approval in the app. The first machine's profiles can manage channels.
- Machines join with a single-use invite and a boss's approval; one approval enrols every
  agent runtime on the machine (Claude Code, Codex, Gemini).
- Several bosses with `admin`, `manager` and `viewer` roles and per-agent grants; archive
  and restore keep identities and grants.
- Agents hold several labelled, revocable keys with safe rotation (`hiboss key`).
- Optional ES256 signing of agent messages and boss replies with device-held keys.

### Decisions and messages

- `hiboss ask` with up to five choices, defaults and timeouts; one durable answer wins,
  and timeout defaults are reported as `auto_default`, never as a human choice.
- Messages, replies, reactions, forwards, attachments and per-session inboxes.
- Peer coordination between agent sessions with `send --to` and `send --broadcast`.
- Delivery to the apps, Telegram and Discord, with quiet hours, priorities and per-boss
  notification destinations.

### Progress, panels and Box

- A per-project progress timeline with images and video that never notifies.
- Live panels: continuously updated cards with leases, lifecycle states, expiry and
  renewal, plus typed questionnaires that agents can wait on.
- Box: the boss's shared text, links and media, searchable by agents, organized in
  collections, with expiring public share links.

### Apps

- iPhone: attention inbox, decisions from notifications, Live Activities and Dynamic
  Island choices, session transcripts, progress, panels, Box, share extension and widgets.
- Mac (HiBoss Island): dashboard, attention island, history, panels, Box, device
  approval, pairing and sign-in with iPhone.
- Web console: agents and keys, bosses and grants, sessions, projects, notification
  destinations, devices and audit log, in English, Chinese, Japanese and Korean.

### CLI 1.13.0

- First-install bootstrap flags `--bootstrap-secret` (or `HIBOSS_BOOTSTRAP_SECRET`) and
  `--boss-name` for `hiboss setup`.
- Box collections (`hiboss box collections new|rename|add|rm`), collection filters and
  likes output, and public share links (`box share`, `box shares`, `box unshare`,
  `box add --share`).
- Agent message signing (`hiboss key enroll`) and per-option descriptions on asks.
- Session nicknames and project avatars; follow-up messages link to the message they
  answer, and actor reactions persist.
- `hiboss setup hooks --global` installs hooks into every Claude Code profile.
- `hiboss ask` honours its timeout across bounded poll windows and shows which device
  answered a decision.
- Guided Discord setup authenticates as the agent and fails on a registration error.
