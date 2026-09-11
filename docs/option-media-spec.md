# Option media — images attached to the choices of an ask

An ask can carry one image per option, so the boss compares two renderings and picks one
("A or B?"). This document is the contract every surface implements: server, CLI, Discord,
Telegram, the boss API clients (iOS, macOS, web console).

## Why it does not work today

Three defects, all confirmed on production data (2026-09-10):

1. Uploaded attachment URLs have no file extension (`/api/attachments/<uuid>`), so
   `isImageUrl()` returns false for every uploaded screenshot. Consequences below.
2. Discord: because the URL does not look like an image, delivery takes the "download the
   file and re-upload it as multipart" path, where the worker fetches **its own**
   `/api/attachments/<key>` URL. That subrequest returned 404 while an external fetch of the
   same URL returned 200 with the correct bytes (mechanism unconfirmed, and it does not need
   to be: the fix removes the self-fetch). The thrown error aborts the whole delivery — the
   boss gets a 502 and no message. Recorded in D1 as
   `metadata.delivery_error = "discord attachment download failed 404"`.
3. Telegram: `deliverToChannelWithOptions()` sends the photo/document and **silently drops
   the inline keyboard**. An ask with an image loses its buttons entirely.

No surface has ever had per-option media; `metadata.options` is a list of labels.

## Wire format

`metadata.option_media` — optional, added next to the existing `options`:

```json
{
  "options": ["压缩文案", "保持不动"],
  "option_media": [
    { "label": "压缩文案", "url": "https://…/api/attachments/<uuid>.png", "caption": "after" },
    { "label": "保持不动", "url": "https://…/api/attachments/<uuid>.png" }
  ],
  "file_url": "https://…/api/attachments/<uuid>.png"
}
```

Rules, enforced server-side in `parseOptionMedia()` next to `parseOptions()`:

- absent → behavior is exactly as today; the field is never invented by the server.
- `option_media` requires `options`; without it → 400.
- 1..5 entries (`MAX_MESSAGE_OPTIONS`), each `label` unique and equal to one of `options`
  after trimming. An unknown label is a 400, never a silently dropped image — a boss who
  cannot see the image cannot answer the question.
- Partial coverage is legal: some options carry an image, others do not.
- `url` must be `http(s)`, ≤ 2048 chars. `caption` optional, ≤ 200 chars.
- `option_media` order does not matter; rendering order is always the order of `options`.
- The label is the identity of the answer everywhere (`callback_data`, `selected_option`,
  the resolution record). Media never becomes an answer value.

`file_url` keeps its current meaning: one message-level attachment, rendered as context
above the choices. It may be combined with `option_media`.

## Attachments must carry an extension

`POST /api/attachments/upload` stores under `<uuid>.<ext>`, with `ext` derived from the
**content type** the server already resolved (`image/png` → `png`, `image/jpeg` → `jpg`,
`image/gif` → `gif`, `image/webp` → `webp`, `video/mp4` → `mp4`; unknown → no extension).
Not from the filename: raw uploads may arrive as `x-filename: upload`, and progress media
converts `.gif` to MP4.

`GET /api/attachments/:key` is unchanged, so every already-stored extension-less object
keeps serving. No migration.

## Rendering

### Discord

- One embed per option that has media, in `options` order:
  `{ title: "A · <label>", description: <caption?>, image: { url } }`, letters A, B, C…
- A message-level image `file_url` is the first embed, before the option embeds.
- Buttons are unchanged — the boss still answers by label.
- The worker must never fetch its own attachments URL over HTTP. For a non-image
  `file_url` that points at `/api/attachments/<key>`, read the object from the
  `ATTACHMENTS` binding directly; only a foreign URL is fetched.

### Telegram

One rule, because the three special cases this replaced each lost something: the question
text, the buttons, or the ability to edit the message afterwards.

- A message **with** an inline keyboard and any media → the media goes first (photo, album
  of 2..10, or document), captions carrying only `A · <label>` plus the per-image caption
  and never the body, then **one text message with the body and the keyboard**.
- A message with **no** keyboard → one message, exactly as before: photo or document
  captioned with the body.

So `metadata.telegram_message_id` is always a plain text message whenever options exist.
That is load-bearing: `message-options.ts` (resolution and expiry), `message-edit.ts` and
`telegram-webhook-actions.ts` all edit that id, and they choose `editMessageText` versus
`editMessageCaption` by whether the message carries options. A photo id stored there makes
the "Selected" annotation fail silently.

### Boss API clients

`metadata` reaches clients as an opaque JSON blob; verify nothing whitelists fields on the
way out (`boss-inbox`, `boss-home`, `boss-option-stream`).

- **HibossKit** — `MessageMetadata` gains `optionMedia: [OptionMedia]` (`label`, `url`,
  `caption`), decoded from `option_media`, defaulting to `[]`.
- **macOS** — the option picker shows a thumbnail beside each labeled choice; clicking one
  opens the full image. Native controls and semantic colours only: `docs/macos-design-v2.md`
  is the contract.
- **iOS** — the decision card shows a two-up comparison above the buttons, tap to zoom.
  **Live Activity and Dynamic Island render labels only**: a Live Activity cannot load a
  remote image, so the comparison lives in the app, and the activity must stay readable
  without it.
- **Web console** — an `<img>` per option in the message options view, wide enough and
  `object-fit: contain`, because a cropped screenshot answers a different question.

A comparison tile must take the width it is offered and never the width of its image. Hang
the aspect ratio off a view with no intrinsic size (`Color.clear.aspectRatio(…).overlay { … }`),
not off the `AsyncImage`: with the ratio on the image, the tile lays out correctly until the
image loads and then adopts the file's natural width — 480pt for an ordinary screenshot —
which pushes every card in the surrounding list off the screen. Both iOS list surfaces and
the message detail page shared that defect, and it is invisible in any test that renders the
component while the image is still loading.

## CLI

```bash
hiboss ask \
  --option "压缩文案"  --option-image "压缩文案=./after.png" \
  --option "保持不动"  --option-image "保持不动=./before.png" \
  --content "filler economics 提示" "A/B 选一个"
```

- `--option-image LABEL=PATH_OR_URL`, repeatable, split at the first `=`.
- The label must match a `--option`/`--action` label; mismatch fails **before** any upload.
- A local path is uploaded through the existing `/api/attachments/upload`; an `http(s)` URL
  is passed through untouched.
- Combines with `--file` (message-level context image).
- At most 5.
- Each upload prints `attached: <label> -> <url>` to stderr, like the existing
  `Uploaded: …` line. Data still goes to stdout only.

## Verification bar

Not "it compiles". A real two-option ask with two images, sent from the CLI, must:

- Telegram: show both images and working buttons; the pick strikes the keyboard.
- Discord: show two labeled embeds and working buttons.
- macOS and iOS: show both thumbnails; the pick resolves with the right `selected_option`.
- D1: `metadata.option_media` present, `metadata.delivery_error` absent.

A shared view has more than one caller, so this list is per *surface*, not per screen: on
iOS the decision card appears in the Home list, the Inbox list and the message detail page,
and a layout bug can live on exactly one of them. Rendering the component on a single screen
at three Dynamic Type sizes is one test, not three.

Status as of 2026-09-11: all of the above confirmed except the Discord render, which is
covered only by unit tests on embed composition — the bot token used here cannot read that
channel back (403).
