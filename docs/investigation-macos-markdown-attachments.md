# Native Markdown attachment reading

KB consulted: `kb macOS markdown attachment preview rendering`.
The native-view rendering record recommends checking rendered output in addition to compilation.

## Confirmed failure

Message attachments previously offered an external file link only. Uploaded document URLs
can end in an opaque identifier, while the actual Markdown filename is provided by
`Content-Disposition`. A UTF-8 Markdown report can therefore arrive as
`application/octet-stream` without an extension in its URL.

## Reading behavior

The iOS and Mac attachment surfaces resolve extensionless file metadata with HEAD and display the
response filename. Markdown attachments offer a native preview sheet while retaining the
original file link. The document is downloaded only when the preview opens.

The reader supports native headings, inline emphasis, links, lists, quotes, fenced code,
and pipe tables. Tables scroll horizontally inside the reading width and preserve column
alignment. Fenced code remains code even when its contents resemble a table.

Download and parsing code is shared in HibossKit. iOS presents a native navigation sheet;
Mac presents a native reading sheet. Both preserve selectable text and the original file link.
Windows line endings are normalized before table parsing.

Downloads require a successful HTTP response and UTF-8 text. Both the advertised size and
streamed byte count are limited to 2 MiB. Loading failures expose retry and original-file
actions. Local filesystem links in an agent's document remain text under the existing
Markdown link policy.

## Verification

A native rendered regression fails when a Markdown attachment has no preview action.
Integration tests cover extensionless octet-stream responses, encoded response filenames,
HTTP failures, invalid UTF-8, and oversized files. Native light and dark render checks
verify visible headings, table cells, code, and a bounded reading width.
