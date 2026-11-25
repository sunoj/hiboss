<!-- Message title bounds, native Markdown reading, and attachment preview behavior.
     Scope: message content transport and native clients; no deployment state. -->
# Message titles and Markdown details

Agent-to-boss messages conventionally use `body` as a short, plain-text title. The current
CLI enforces at most 144 Unicode scalar values after trimming surrounding whitespace. Spaces and
punctuation count. A Chinese character or a single-scalar emoji counts once; a composed
emoji can contain multiple scalars. The server accepts longer bodies from older clients
on send, blocking ask, and edit, retaining the full body after trimming surrounding
whitespace without moving it into metadata. Boss replies and agent-to-agent message
bodies keep their existing full-text behavior.

Clients can supply complete Markdown details in `metadata.content`. The private notification
preview in `metadata.summary` is independent; it does not create body content.

```sh
hiboss send "House update" --content-file /absolute/path/report.md
hiboss ask "Which layout should ship?" --content-file /absolute/path/comparison.md \
  --option "A" --option "B"
```

`--content` also accepts inline Markdown. It cannot be combined with `--content-file`.
The file must contain UTF-8 text. File content is transmitted intact, including newlines
and code-block whitespace; it is not a file attachment.

Native iOS and macOS message reading supports paragraphs, ATX headings, emphasis,
inline code, links, ordered and unordered list items, blockquotes, fenced code, and copy
blocks (below).
Text uses native semantic fonts, selection, and Dynamic Type. HTML is not executed.
Tables, nested-list indentation, and embedded Markdown images are not rendered as rich
blocks. File/image attachments continue to use message attachment metadata.

Links are underlined. A bare `http://` or `https://` URL becomes a link in message text,
titles, notes and progress posts. It ends at the first non-ASCII character or space, and
trailing `. , ; : ! ? ' "` and unbalanced `)` or `]` stay outside it, so
`https://example.com/a，下载` links only `https://example.com/a`. URLs inside inline code stay text.

## Copy blocks

A fenced block whose info string starts with the word `copy` is a copy block. The rest of
the opening line is an optional label. Native iOS and macOS clients render the block as
wrapped monospaced text with a copy button; the button copies the block text exactly as
written, including inner whitespace, and the text is never truncated.

````markdown
Point the CLI at staging:

```copy Staging server
https://staging.example.com
```
````

- Only the exact word `copy` qualifies: `copyright`, `copy-x` and `Copy` stay ordinary code.
- `~~~copy` works as well. CRLF line endings are copied as LF.
- A block with no closing fence, such as a cut-off preview, renders as ordinary code with
  no copy button, because its text may be incomplete.
- Channels and clients without copy support show the block as plain fenced code, so the
  value stays readable and selectable.

The 144-scalar title is a client-side convention. Native iOS and macOS clients derive
a bounded heading from a long body on display and preserve the original text in the details.

## Markdown file attachments

Both native clients offer a Markdown preview for `.md` and `.markdown` attachments.
Recognition uses the response filename or Markdown MIME type as well as the URL suffix,
so an opaque upload URL can still identify a Markdown document.

The attachment renderer supports tables in addition to native Markdown text blocks.
Wide tables scroll horizontally. Each row measures its cells at their resolved column
widths, keeping multiline cells separate from the next row at larger text sizes.
This table rendering applies to attachment previews; inline message content keeps the
block support described above.

Preview reads are limited to 2 MiB and require UTF-8 text. Loading errors offer retry;
the original-file action remains available. HTML is not executed.

## Codex session attribution

The CLI detects Codex through `CODEX_THREAD_ID`, falling back to `CODEX_SESSION_ID`.
Each thread uses separate local session state and selects the configured `codex`
profile. A first send without session state registers the execution session from the
project checkout before delivery; registration errors stop that send.

```sh
hiboss whoami
hiboss setup hooks --runtime codex --global
```

Hook setup writes `${CODEX_HOME:-~/.codex}/hooks.json` and its managed `AGENTS.md`
guidance, preserving unrelated hooks. The hook adapter reads `session_id` and `cwd`
from Codex's JSON input and returns model-visible JSON context. Codex requires review
and trust of new hook definitions through `/hooks`; installation does not grant trust.
See [official OpenAI documentation](https://learn.chatgpt.com/docs/hooks).

## Embed cards

`metadata.rich_content` is a server-owned variant of `metadata.content`. Clients that draw
cards show it instead of `content`; channels and older clients keep using `content`, which
carries the same information as plain Markdown. Clients cannot set `rich_content`.

In `rich_content`, a closed fenced block whose info string is exactly `hiboss-embed` holds one
card as a single line of JSON: `color` (0xRRGGBB or null), `title`, `url`, `author`,
`description`, `fields` (`name`, `value`, `inline`), `image`, `thumbnail`, `footer`, and
`timestamp` (ISO 8601). A block holding only `text` is plain Markdown without card chrome. Text
values are Markdown, rendered with cards disabled, so text inside a card never draws another card. Native clients draw a card with a coloured
edge, the title (linked when `url` is set), the description, the fields (up to three inline
fields per row, other fields on their own row) and the footer with the local time. A block that
is unclosed or whose JSON does not decode renders as ordinary code.
[Discord-compatible webhooks](discord-webhooks.md) produce these cards.
