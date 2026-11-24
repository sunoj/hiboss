# Discord-compatible webhooks

A tool that can post to a Discord webhook URL can post to HiBoss instead: replace
`https://discord.com/api/webhooks/{id}/{token}` with `https://<hiboss-host>/api/webhooks/{id}/{token}`.
The post lands in the boss's apps as a message from an **integration**, grouped in that
integration's own session, with each embed drawn as a card.

This works for any sender whose Discord webhook URL is a free-form setting, such as Grafana
alerting, Uptime Kuma, GitHub Actions that take a webhook URL, and curl scripts. Senders that
hard-code `discord.com` (shoutrrr and therefore Watchtower, Apprise) and Discord integrations
that use a bot (Sentry) cannot be redirected.

## Integrations and URLs

An integration is an agent identity with `kind = 'integration'`. It holds no agent keys and no
signing keys, owns one project and one idle session, and is created by an admin agent:

```bash
hiboss integration create "Grafana prod" [--priority low|normal|high]   # prints the URL once
hiboss integration list                                                 # never shows tokens
hiboss integration add-url <agent-id> <label> [--priority …]            # another URL, same session
hiboss integration rotate <webhook-id>                                  # old URL stops at once
hiboss integration revoke <webhook-id>
```

- The URL is the credential. Its token (64 characters) is stored only as a hash and is shown
  once. It is send-only: it is never accepted as a bearer key, cannot read messages, reply,
  ask a question or register a session.
- An unknown id, a wrong token and a revoked URL all answer `404 {"message":"Unknown Webhook","code":10015}`.
- The server error log replaces the token in a webhook path with `***`.
- Admin bosses receive integration messages; a manager needs an explicit agent grant.
- A boss reply to a webhook message is refused with 409: nobody would read it.
- Integrations are not `--to` targets, cannot join groups, do not receive group broadcasts or
  boss notes (409), and do not appear among a session's peers.
- Revocation and rotation take effect for the next request; a post already authenticated before
  the change may still be stored.
- Responses from the endpoint and from `/api/integrations` carry `Cache-Control: no-store`.

## Endpoint

`POST /api/webhooks/{id}/{token}` (also `/api/v{n}/webhooks/…`), with `{id}` 17–20 digits.

| Input | Behaviour |
|---|---|
| `application/json` | The Discord Execute Webhook body |
| `multipart/form-data` | `payload_json`, or the fields as separate parts; any part with a filename is a file, whatever its field name |
| `content` (≤ 2000), `embeds` (≤ 10), `username`, `flags`, `thread_name` | Used as below; other fields (`components`, `poll`, `tts`, `allowed_mentions`, `avatar_url`, …) are ignored |
| Empty `content` and no embeds or files | `400 {"code":50006}` |
| Malformed JSON or form | `400 {"code":50035}` |
| Unknown id, wrong token or revoked URL | `404 {"code":10015}` before the body is read |
| More than 30 posts in the current minute (per integration, reserved atomically before the body is read) | `429 {"retry_after":60,"global":false}` with `Retry-After` and `X-RateLimit-*` |
| Body over 256 KB (JSON or URL-encoded), a text part over 256 KB, more than 20 parts, or over 8 MB (multipart) | `413 {"code":40005}` or `400 {"code":50035}`; the cap is counted while reading, not taken from `Content-Length` |
| `payload_json` that is not valid JSON | `400 {"code":50035}` |
| `?wait=true` | `200` with a minimal message object; otherwise `204` |

`GET` on the same URL returns the webhook object (`id`, `type: 1`, `name`, `token`). `PUT`,
`PATCH` and `DELETE` answer 405.

Over-long input is clamped to Discord's limits and marked *truncated* instead of rejected, so an
alert is not lost to a 400.

## The message

| Discord | HiBoss |
|---|---|
| First of: `embeds[0].title`, first line of `content`, first line of `embeds[0].description`, `embeds[0].author.name`, the integration name | Message title (≤ 144 characters, Markdown removed) |
| `content` and embeds | `metadata.content`: plain Markdown for channels and older apps |
| `content`, each embed, and the closing notes | `metadata.rich_content`: only server-written `hiboss-embed` blocks, one JSON line each (see [message format](message-format.md)); sender text is never raw Markdown there |
| `username` | A trailing *via …* line; the sender stays the integration |
| `flags & 4096` (`SUPPRESS_NOTIFICATIONS`) | Priority `low`; otherwise the URL's priority (default `normal`) |
| Files (any field name, including Grafana's empty one) | Listed by name and size; never stored, so a URL cannot be used to host bytes |
| `<t:…>`, `<@…>`, `<#…>`, `<:emoji:…>`, `-# ` | UTC time, `@user`, `#channel`, `:emoji:`, plain text |
| A sender's own ```` ```hiboss-embed ```` fence | Becomes an ordinary ```` ```text ```` fence: only the server writes cards |

Messages are `agent_to_boss`, `async`, never asks, and carry provenance
`{source: 'webhook', authentication: {kind: 'webhook_token', credential_id: <webhook id>}}`.
Each accepted post sets the integration session's status text to the title; the session stays `idle`.
