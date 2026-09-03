# Push Isolation & Privacy (self-hosted APNs)

hiboss is **self-hosted, single-tenant** (see the architecture decisions): one operator
= one Cloudflare Worker + one D1 + one Apple Developer team. This note explains how iOS
push stays isolated per deployment and what "message encryption" does and doesn't buy us.

## 1. Isolation is structural, not a feature

Each deployment is a closed loop with no shared backend:

```
your agents ──► your Worker ──► your D1 (messages, bosses, boss_devices)
                     │
                     └─ APNs (your .p8 key) ──► your app build ──► your iPhone
```

- **Data**: `boss_devices` (APNs tokens), `bosses`, and `messages` live in *your* D1 only.
  A device token registered against server A exists only in server A; server A pushes only
  to its own rows. Nothing crosses deployments.
- **Auth**: the boss token authenticates to exactly one server; agent keys likewise. Device
  registration (`POST /api/boss/devices`) requires the boss token.
- **Transport**: agent↔server and client↔server are HTTPS; APNs is TLS to Apple.

## 2. The APNs constraint that actually matters

APNs delivery is bound to the **app's bundle ID**, which is owned by **one Apple Developer
team**. An APNs auth key (`.p8`) can only push to app IDs of the team that created it.

**Consequence:** the first-party build `ai.hiboss.app` (team `JHH9GC8Y8C`) can only be pushed
to by that team's APNs key. A different operator **cannot** push to `ai.hiboss.app` with their
own key — and you should not hand out your key, because whoever holds it can push to every
install of that bundle ID. So:

- **Correct self-hosted model:** each operator ships **their own app build** — their own
  bundle ID (e.g. `com.acme.hiboss`), their own signing team, their own APNs key — and points
  it at their own server. Full isolation, no shared push plane. This is the honest
  self-hosted story (you build the client, like any self-hosted app).
- The published `ai.hiboss.app` is a **first-party/reference client** tied to our team. Others
  can point a build at their server for in-app SSE/history, but **push** requires their own
  bundle ID + key.

There is deliberately **no central push relay** — that would reintroduce multi-tenancy, which
we've ruled out.

## 3. Do we need message encryption?

Transport is already encrypted. The real exposure is the **push payload's alert body**: to be
shown in a banner it must be **plaintext**, and it passes through Apple's servers. So today the
(truncated) message body is visible to Apple.

You cannot encrypt the *visible* alert text and still have iOS render it. The practical options:

| Approach | Protects against | Cost / caveat |
|---|---|---|
| **A. Minimal-payload push (recommended)** | Apple seeing content | Push carries only a generic title + `messageId`; the app fetches the full body from *your* server over TLS (already how deep-link/history works). Small server change. |
| **B. Content-at-rest encryption in D1** | Server/D1 compromise | Conflicts with Telegram/Discord channels, which need plaintext to render. Only viable if push/app is the *sole* channel. |
| **C. End-to-end (agent→boss) encryption** | Everyone in the middle | Heavy key management; breaks channel fan-out and server-side routing. Overkill for this tool. |

**Recommendation:** add a per-boss **"private notifications"** preference that switches to
approach A — the push says only "New decision from `<agent>`" (or nothing but a count) plus the
`messageId`, and the app pulls the content from your own server. That keeps sensitive text off
Apple's infrastructure **without** breaking the multi-channel (Telegram/Discord) model. Full
E2E (B/C) is unnecessary given the self-hosted, single-tenant design.

### Implementation sketch for approach A
- `BossPreferences` gains `privatePush: Bool` (default false).
- `server/src/notify.ts` `buildBossPushPayload`: when private, set
  `alert.body = "New decision"` (or agent name only), keep `messageId`/`options` out of the
  visible text but still in `userInfo` for the deep-link.
- No client change needed — tapping already fetches the full message via the detail deep-link.

## TL;DR
- Isolation is structural: own server + own D1 + **own app build + own APNs key**. Don't share
  a `.p8` across operators.
- You don't need message encryption for correctness; you need a **minimal-payload push option**
  if you want message *content* kept off Apple's servers. Everything else is already TLS and
  single-tenant.
