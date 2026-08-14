# Progress attribution — which agent, which model

Extends `docs/progress-feed-contract.md` and `docs/progress-feed-v2-contract.md`. A progress
post should say **who did the work**: the agent tool that produced it and the LLM behind it.

## Decisions already made (do not relitigate)

| Decision | Choice |
|---|---|
| Fields | Two nullable columns on `progress_posts`: `agent_label`, `model`. |
| Source | The CLI **detects** them; flags only override. An agent should not have to remember. |
| Missing values | Omit from the UI entirely. Never render "unknown". |
| Vendor mark | A vendor-coloured monogram drawn natively — **not** a bundled brand logo. See below. |

### Why a monogram and not the real logos

This repo is planned for open source. Vendor logos are trademarks, and redistributing them in
a public repository is a real risk that a UI detail does not justify. Draw a small monogram
chip tinted per vendor instead, and keep the rendering behind one view so a real asset can
replace it later if the owner decides to take that on. Do not download or vendor any brand
asset in this change.

## Detection — verified, not assumed

**Claude Code** (measured on this machine):
- `CLAUDECODE=1` and `CLAUDE_CODE_ENTRYPOINT` mark the harness → `agent_label = "claude-code"`.
- The environment does **not** carry the model. It is in the session transcript:
  `~/.claude/projects/<cwd with '/' replaced by '-'>/<CLAUDE_CODE_SESSION_ID>.jsonl`, where
  `assistant` records carry `message.model` (observed value: `claude-opus-5`). Read the
  **last** such record; the model can change mid-session.
- Treat that file as read-only, best-effort, and possibly absent. It is the user's private
  transcript: read only the `model` field, never log or transmit any other part of it.

**aid-dispatched agents**: aid knows the route as `<cli>/<provider>/<model>`. Determine what
it actually exposes to a dispatched task's environment — check, don't guess — and use it when
present.

**Neither available**: omit both fields. A missing attribution is fine; a wrong one is not.

Detection must never slow down or fail a post. Wrap it so any error, missing file, or
malformed line results in `None`, not a failure.

## Server

Add `agent_label TEXT` and `model TEXT` to `progress_posts` (migration `0029`, mirrored in
`schema.sql`). Accept both as optional strings on `POST /api/progress` (max 64 chars each,
reject anything longer). Echo both on every post response, `null` when absent. No other
behaviour changes.

## CLI

`hiboss progress post` gains `--agent <label>` and `--model <name>` which **override**
detection. Detection runs otherwise. `progress list` shows them compactly after the handle.

## iOS

In the post byline, after `display name · @handle · time`, show a small attribution chip:
a vendor monogram plus the model name, in a secondary style that does not compete with the
body. Long model names truncate rather than wrap. When only one field is present, show that
one. When neither is present, the chip does not exist — no placeholder, no empty space.

Vendor is derived from the model string on the client (e.g. `claude-*` → Anthropic,
`gpt-*`/`o*` → OpenAI, `gemini-*` → Google, `grok-*` → xAI); an unrecognised model gets a
neutral chip rather than a guess. Keep that mapping in one place.

Native-first (`docs/macos-design-v2.md`) still binds. New strings go through the String
Catalog with zh-Hans / ja / ko (ja/ko needs-review).

## Out of scope

Per-model filtering, cost or token attribution, showing the provider/route separately, and
any backfill of existing posts (they simply have no attribution).
