# Box public share links — contract

A share link lets anyone holding the URL view one Box item without signing in, until it expires or is
revoked. The server stores only a hash of the token. Agent-created links remain valid until expiry or
revocation even if the agent later loses access. The boss can list and revoke these links. Every link of
an archived boss stops working while the boss is archived, and works again after a restore if it has not
expired or been revoked.

## Data (migration 0057_box_shares.sql, additive)
`box_shares`: `id` TEXT PK (`bs_` + 32 hex), `item_id` TEXT NOT NULL → box_items.id, `boss_id` TEXT NOT NULL,
`token_hash` TEXT NOT NULL UNIQUE (hex SHA-256 of the token string), `created_by_agent` TEXT NULL
(NULL = boss), `created_at`, `expires_at` (ISO, NOT NULL), `revoked_at` NULL, `view_count` INTEGER
DEFAULT 0, `last_viewed_at` NULL. Index on `item_id`.

## Token
32 bytes from `crypto.getRandomValues`, base64url without padding (43 chars). Returned only in the create
response; never stored, logged or listed.

## Authenticated API (under the existing `/api/box` router, `dualAuth`)
- `POST /api/box/items/:id/shares` body `{ "ttlSeconds"?: number }`; default 604800 (7 d), allowed
  3600..2592000 (1 h..30 d), else 400. The item must be readable by the caller AND `canEditItem` (boss: any
  item of that boss; agent: only items it added). Otherwise 404. Deleted items: 404.
  201 → `{ "id", "itemId", "url", "expiresAt", "createdAt" }`, `url` = `<request origin>/s/<token>`.
- `GET /api/box/items/:id/shares` → `{ "shares": [{ "id", "itemId", "createdAt", "expiresAt",
  "revokedAt", "createdBy": "boss" | "<agent name or id>", "viewCount", "lastViewedAt", "active" }] }`
  (no token, no URL). Same access rule as create.
- `DELETE /api/box/shares/:shareId` → 204. Boss: any share of that boss. Agent: only shares it created.
  Otherwise 404. Idempotent: revoking a revoked share is 204.

## Public routes (no auth), mounted in server/src/index.ts
- `GET /s/:token` → HTML page for the item. `GET|HEAD /s/:token/file` → the item's bytes (Range support
  via the existing `serveAttachment`).
- A share is valid only when: token hash matches, `revoked_at IS NULL`, `expires_at > now`, the item exists
  and is not deleted, and the owning boss is not archived (`bosses.archived_at IS NULL`). Every failure → the same 404 page/body (no distinction between expired, revoked and
  unknown).
- Count a view on the page GET only (not on `/file`, not HEAD): increment `view_count`, set `last_viewed_at`.
- Page content: title (escaped), text body in `<pre>` (escaped), link items as an `<a>` only when the URL is
  `http:`/`https:` (`rel="noopener noreferrer nofollow"`), images `<img src="./<token>/file">`, video
  `<video controls>`, other files a download link with size and type. Expiry date shown. No scripts.
  Minimal inline CSS; readable on a phone; light/dark via `prefers-color-scheme`.
- Headers on every `/s/*` response: `Cache-Control: private, no-store`, `X-Robots-Tag: noindex, nofollow`,
  `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff`.
  Page CSP: `default-src 'none'; img-src 'self'; media-src 'self'; style-src 'unsafe-inline';
  base-uri 'none'; form-action 'none'; frame-ancestors 'none'`.
  File CSP: `default-src 'none'; sandbox; frame-ancestors 'none'`. `Content-Disposition: inline` only for
  image/png, image/jpeg, image/gif, image/webp, image/heic, video/mp4, video/quicktime; everything else
  (including SVG, HTML and PDF) `attachment` with a safe filename and `application/octet-stream`.
  PDFs are served as downloads.
- Text and link items have no `/file`: 404.

## CLI (`hiboss box …`)
- `hiboss box share <item-id> [--ttl <1h|12h|7d|30d|…>]` → prints the URL on stdout and the expiry on stderr.
- `hiboss box add … --share [--ttl …]` → after the item is created, creates a share and prints its URL as
  the last stdout line, labelled `share: <url>`. With `--json`, the share is a second JSON line.
- `hiboss box shares <item-id>` → table of shares (id, created, expires, views, active).
- `hiboss box unshare <share-id>` → revokes.
- `--json` where the existing Box commands support it.
- Help text says plainly: anyone with the link can view the item until it expires or is revoked.
