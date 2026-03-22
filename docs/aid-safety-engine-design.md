# DESIGN: aid Safety Rules Engine

## Overview
The `aid` Safety Rules Engine is a runtime protection layer designed to enforce security invariants and project standards during AI agent execution. It focuses on declarative, human-readable rules that prevent common failure modes like secret leakage and mass file corruption.

## 1. Specification: `aid-safety.toml`

The configuration uses a declarative format to define rules, triggers, and actions.

```toml
# Rules are evaluated in order. First match (deny) wins.

[[rule]]
id = "protect-secrets"
description = "Prevent agents from reading or writing sensitive files"
type = "path_match"
action = "deny"
patterns = [
  ".env*",
  "**/.ssh/*",
  "**/id_rsa*",
  "**/*.pem",
  "config/database.yml"
]
# Modes: read, write, delete, execute
modes = ["read", "write", "delete"]

[[rule]]
id = "taint-network-after-secret"
description = "If a secret was read, block outbound network calls for the session"
type = "stateful_sequence"
condition = { event = "file_read", patterns = [".env*"] }
action = { block = "network_call" }
scope = "session"

[[rule]]
id = "mass-edit-guard"
description = "Halt if the agent attempts to modify too many files"
type = "resource_limit"
metric = "files_modified"
limit = 20
action = "halt"

[[rule]]
id = "test-coverage-enforcement"
description = "Require matching test files for new implementation files"
type = "post_condition"
on = "file_create"
match_pattern = "src/**/*.rs"
validate_command = "ls tests/$(basename $FILE .rs)_test.rs"
action = "warn"
```

## 2. Enforcement Architecture

The engine integrates into the `aid` tool execution loop via three distinct phases:

### Phase A: Static Pre-Check (Filter)
Before a tool is invoked, its arguments are checked against `path_match` rules.
- **Input:** Tool name + Arguments.
- **Action:** If a `deny` pattern matches, the tool call is rejected before reaching the OS/Shell.

### Phase B: Stateful Runtime Monitoring (Interceptors)
A "Taint Tracker" maintains a session-local state of critical actions.
- **State Store:** In-memory or `store.db`.
- **Logic:** `on_event(FileRead(".env")) -> set_state(has_seen_secret, true)`.
- **Enforcement:** If `has_seen_secret` is true, all subsequent `network_call` events are blocked.

### Phase C: Post-Action Audit (Verify)
After a tool execution completes, the engine inspects the side effects.
- **Diff Audit:** For `file_write`, check the number of lines/files changed.
- **Script Validation:** Run external checks (e.g., `cargo check`, `grep`) to verify invariants.

## 3. Implementation Plan (for `ai-dispatch` repo)

1. **`src/safety/rules.rs`**: Define `SafetyRule` enum and `RuleSet` struct with `serde` support for TOML.
2. **`src/safety/engine.rs`**: The core evaluator. Implements `check_call(&self, call: &ToolCall, state: &SafetyState) -> SafetyDecision`.
3. **`src/safety/state.rs`**: Tracks session context (files touched, secrets seen, tool counts).
4. **`src/agent/executor.rs`**: Modify the execution loop to call `safety_engine.check_call()` before and after tool execution.

## 4. Test Strategy

| Scenario | Expected Result |
| :--- | :--- |
| Read `.env` | Blocked by `protect-secrets` |
| Read `src/main.rs` then `curl google.com` | Allowed |
| Read `.env` (bypass filter) then `curl` | Blocked by `taint-network` |
| Modify 21 files in one task | Session halted by `mass-edit-guard` |
| Create `src/auth.rs` without `tests/auth_test.rs` | Warning issued in task log |

[MILESTONE] Safety Engine Design Finalized
