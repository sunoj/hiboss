# aid x hiboss Integration Guide

How to connect [aid](https://github.com/agent-tools-org/ai-dispatch) (multi-AI CLI orchestrator) with hiboss for rich notifications, interactive approvals, and autonomous orchestration.

## Current State

aid v8.6+ has built-in hiboss support via `notify.rs`. When enabled, task completions trigger `hiboss send` with status, cost, and duration.

```
aid task completes → notify_hiboss() → hiboss send "Task t-abc DONE: ..." → Discord/Telegram
```

## Setup

### 1. Install hiboss CLI

```bash
cd /path/to/hiboss/cli
cargo build --release
cp target/release/hiboss ~/.cargo/bin/
hiboss init https://your-hiboss-server.workers.dev
hiboss channel set telegram --bot-token <TOKEN> --chat-id <CHAT_ID>
```

### 2. Enable in aid config

Add to `~/.aid/config.toml`:

```toml
[hiboss]
enabled = true
priority = "normal"
# Optional: customize the message template
# template = "Task {id} {status}: {prompt_truncated} ({duration}, {cost})"
```

Template variables: `{id}`, `{status}`, `{prompt_truncated}`, `{duration}`, `{cost}`.

### 3. Configure channel routing (recommended)

Route normal notifications to Discord, urgent ones to Telegram:

```bash
hiboss agent config --channel-routing "normal=discord,high=telegram,critical=telegram"
```

## Integration Layers

### Layer 1: Rich Notifications (aid-side changes only)

Enhance `notify_hiboss()` to use hiboss features that already exist:

| Event | Priority | Type | Example |
|-------|----------|------|---------|
| Task success | normal | `aid_task_complete` | `Task t-abc DONE: implement feature (2m, $3.50)` |
| Task failure | high | `aid_task_fail` | `Task t-abc FAIL: cargo check failed` |
| Workgroup complete | normal | `aid_wg_complete` | `Workgroup wg-123: 3/3 done, $12.50 total` |
| Budget alert | critical | `aid_budget_alert` | `Budget 80% consumed: $800/$1000` |

**Implementation**: Change `notify.rs` to pass `--type` and smarter `--priority`:

```rust
// Current (fire-and-forget, plain text):
cmd.arg("send").arg("-p").arg(&config.hiboss.priority).arg(&message);

// Enhanced:
let (priority, msg_type) = match task.status.label() {
    "done" => ("normal", "aid_task_complete"),
    "fail" | "error" => ("high", "aid_task_fail"),
    _ => ("normal", "aid_task_update"),
};
cmd.arg("send")
   .arg("--priority").arg(priority)
   .arg("--type").arg(msg_type)
   .arg(&message);
```

**Diff attachments**: For merge-ready tasks, attach the diff:

```rust
// After generating diff file:
cmd.arg("send")
   .arg("--file").arg("/tmp/aid-diff-t-abc.txt")
   .arg("--type").arg("aid_merge_ready")
   .arg(&message);
```

**No hiboss changes needed** -- all features (`--type`, `--priority`, `--file`) already exist.

### Layer 2: Interactive Approvals (aid-side changes only)

Use `hiboss ask --actions` to let the boss approve/reject from Telegram/Discord:

```bash
# Merge approval with action buttons
hiboss ask --actions "Merge:aid merge t-123 --yes,Retry:aid retry t-123,Skip" \
  "Task t-123 ready to merge:
- Agent: codex
- Files: src/foo.rs, src/bar.rs
- Diff: +120 -30

Approve?" --timeout 300
```

Boss taps "Merge" in Telegram → `aid merge t-123 --yes` executes → result auto-sent back.

**Best-of winner selection**:

```bash
hiboss ask --options "codex ($3.20),opencode ($0.50),cursor ($2.10)" \
  "Best-of-3 complete for 'implement retry logic'. Pick winner:" \
  --timeout 300
```

**Implementation in aid**: Add a `post_task_hook` or extend `notify.rs`:

```rust
fn notify_merge_ready(task: &Task) {
    let diff_stat = get_diff_stat(task);  // +120 -30 in 3 files
    let body = format!(
        "Task {} ready to merge:\n- Agent: {}\n- {}\n\nApprove?",
        task.id, task.agent_display_name(), diff_stat
    );
    let mut cmd = Command::new("hiboss");
    cmd.arg("ask")
       .arg("--actions")
       .arg(format!("Merge:aid merge {} --yes,Retry:aid retry {},Skip", task.id, task.id))
       .arg(&body)
       .arg("--timeout").arg("300");
    // Fire and forget -- action result auto-sent by hiboss
    let _ = cmd.spawn();
}
```

### Layer 3: Agent-as-Boss (orchestration loop)

Claude Code acts as dev manager, orchestrating sub-agents through aid + hiboss:

```
Claude Code (orchestrator, has its own hiboss API key)
  ↓ aid run codex "implement feature"
  codex working...
  ↓ hiboss ask "stuck on type error, option A or B?" (sub-agent → boss-agent)
  ↑ Claude Code receives via boss inbox → decides → replies
  codex continues with guidance
  ↓ task complete → hiboss send "done" → notifies orchestrator
  Claude Code → aid show → aid merge
```

**Setup**:

```bash
# 1. Create API keys for orchestrator and sub-agents
hiboss agent create orchestrator  # → hb_orch_key
hiboss agent create codex-worker  # → hb_codex_key

# 2. Link orchestrator as a boss
hiboss boss add "Orchestrator" --role admin --agent-id <orch-key-id>

# 3. Sub-agents use their own keys
# In sub-agent's hiboss config: key = hb_codex_key

# 4. Orchestrator polls for sub-agent messages
hiboss boss inbox
hiboss boss reply <msg-id> "Use option A"
```

**Key design insight**: Agent-as-boss is for multiple independent Claude Code sessions communicating, not for managing aid's internal sub-processes. aid manages its own workers (codex, gemini, etc.) via PTY/filesystem. hiboss connects the independent sessions.

## Channel Routing for aid

Recommended routing for aid notifications:

```bash
hiboss agent config --channel-routing "normal=discord,high=telegram,critical=telegram"
```

| aid Event | hiboss Priority | Channel |
|-----------|----------------|---------|
| Task success | normal | Discord |
| Task failure | high | Telegram |
| Budget alert | critical | Telegram |
| Merge approval | normal (ask) | Telegram (use `--channel telegram`) |

**Tip**: `hiboss ask` uses normal priority by default. For interactive approvals that
need quick boss response, use `--channel telegram` explicitly.

## Metadata Conventions

aid can pass structured data via hiboss `metadata` (arbitrary key-value JSON). No special
schema needed -- just include what's useful:

```bash
hiboss send --type aid_task_complete \
  '{"metadata": {"task_id": "t-abc", "agent": "codex", "cost_usd": 3.50, "duration_ms": 120000}}'
```

Or keep it simple with well-formatted message bodies -- hiboss is a transport layer,
not a rendering engine. aid should format its own messages.

## Existing hiboss Features aid Can Use Today

| Feature | How aid Uses It | hiboss Command |
|---------|----------------|----------------|
| Typed messages | Categorize notifications | `--type aid_task_complete` |
| Priority routing | Urgent = Telegram, normal = Discord | `--priority high` |
| File attachments | Send diffs, logs | `--file /tmp/diff.txt` |
| Action buttons | Merge/retry/reject from chat | `--actions "Merge:aid merge t-1"` |
| Action feedback | Boss sees command result | Automatic after button press |
| Quick-reply options | Best-of winner selection | `--options "codex,opencode"` |
| Session isolation | Per-session message scoping | Automatic via session_id |

## Implementation Priority

1. **Enable `[hiboss]` in aid config** -- works today with zero code changes
2. **Smarter priority mapping** -- change `notify.rs` to use `--priority high` for failures
3. **Add `--type`** -- pass message types for better organization
4. **Interactive approvals** -- use `hiboss ask --actions` for merge workflows
5. **Agent-as-boss loop** -- for autonomous multi-session orchestration
