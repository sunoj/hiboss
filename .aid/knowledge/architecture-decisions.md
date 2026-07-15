# Architecture Decisions

## Agent-as-Boss (v0.10)

Agent-as-boss is about **multiple independent Claude Code sessions communicating**, not about managing aid sub-agents. aid manages its own workers via PTY/filesystem.

- Boss-agent hooks check `hiboss boss inbox`
- Don't conflate aid task management with hiboss message routing
- aid's `[hiboss]` config (notify.rs) is for status updates TO human boss, not inter-agent comms

### aid Integration Points
- `src/notify.rs` (notify_hiboss), `src/config.rs` (HibossConfig), `~/.aid/agents/hiboss-relay.toml`
- aid project location: `/Users/mingsun/Develop/ai/ai-dispatch/`

## Design Principles

### Agent Autonomy
Server exposes capabilities (APIs), agents decide behavior. Don't hardcode automatic behaviors.
- No auto-reactions in server (agents call `react` when they choose)
- Hooks on agent side use APIs — that's agent-decided, not server-decided

### Multi-Agent First
Every design decision assumes multiple agents. API keys carry agent names/identities. Inbox shows which agent sent each message.

### Self-Hosted Open Source
No billing, rate limiting, SaaS features, or multi-tenant isolation. Focus on easy self-deployment (Cloudflare Workers free tier).

### No Built-in Email
Email well-served by external CLIs (agentmail-cli, resend). Only Discord and Telegram as built-in channels.

### Hook Resilience
Hooks must NEVER produce errors. Always exit 0 with graceful fallbacks. Write TTL timestamps before checks to prevent retry storms.

### Convergent Option Selection
Option messages use fan-out delivery with a single global resolution state:
- Every Boss SSE connection receives every currently active option message.
- Delivery is never claimed by one client; only selection is exclusive.
- Selection uses an atomic conditional update, so exactly one client wins.
- A resolved or expired parent disappears from every stream through a `resolved`
  event, and external Discord/Telegram controls are withdrawn as best-effort side
  effects.
- Option values are structured arrays. Never infer choice boundaries from commas.

### Webhook Security (v1.1.0)
Webhook endpoints validate request origin via optional secret tokens:
- `TELEGRAM_WEBHOOK_SECRET` — checked against `X-Telegram-Bot-Api-Secret-Token` header
- `DISCORD_WEBHOOK_SECRET` — checked against `X-Webhook-Secret` header
- Both are backwards compatible: if env var is not set, check is skipped
- Discord Interactions endpoint uses Ed25519 signature verification (unchanged)
