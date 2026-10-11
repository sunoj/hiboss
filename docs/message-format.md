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
inline code, links, ordered and unordered list items, blockquotes, and fenced code.
Text uses native semantic fonts, selection, and Dynamic Type. HTML is not executed.
Tables, nested-list indentation, and embedded Markdown images are not rendered as rich
blocks. File/image attachments continue to use message attachment metadata.

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
