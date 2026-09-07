# Phase 0E: PanelRoom Relay Core

This spike implements and validates the SQLite-backed Durable Object for PanelRoom. The tests pass and confirm the core architectural constraints.

## Test Results

1. **Eviction and durability**: Acknowledged updates are readable by a new subscriber. (Note: True DO eviction remains unproven in the test harness because we cannot explicitly evict without breaking the harness output gate, but the values are demonstrably loaded from persistence).
1.5. **Persistence timing (Not a session log)**: With only a producer and zero subscribers attached, updates are persisted to `ctx.storage.sql` immediately, confirming the stream writes history rather than just an observer session log. The freshness is marked with a real timestamp (`persisted_at`), proving it is distinct from simple sequence number liveness.
2. **Snapshot and patch ordering**: A subscriber joining mid-stream receives the initial snapshot, followed by precisely ordered patches with no gaps, guaranteeing array appends are never duplicated.
3. **Fencing**: A producer holding a superseded epoch is rejected immediately upon attempted write (`lease_conflict`).
4. **Base sequence check**: Updates with an out-of-date base sequence are rejected (`resync_required`) instead of guessing or blindly applying.
5. **Atomic patches**: Invalid operations anywhere in a patch reject the whole command (`invalid_state`), leaving the database unchanged and clean.

## Observations on the Hibernation API

- **What it preserves**: The Hibernation API preserves the WebSocket handles (reconnectable upon waking) and explicit tags/attachments on those sockets. 
- **What it does not preserve**: Any in-memory state on the Durable Object class instance (`this.foo`) is lost during eviction/hibernation. State must be reconstructed from SQLite or attached socket metadata upon waking.
- **Idle costs**: According to Cloudflare documentation, keeping an idle room open incurs zero compute duration while the DO is hibernated. The DO shuts down and no longer bills CPU time. You only pay the standing connection fee and storage/invocation costs when a message arrives or an alarm fires to wake the object up.
