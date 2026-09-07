# Phase 0E: PanelRoom Relay Core

This spike implements and validates the SQLite-backed Durable Object for PanelRoom. The tests pass and confirm the core architectural constraints.

## Test Results

1. **Eviction and durability**: Acknowledged updates survive eviction. Because the DO relies strictly on `ctx.storage.sql` and writes synchronously before broadcasting, restarting the DO (simulated by clearing instance state) drops no data. A new subscriber receives the latest persisted snapshot.
2. **Snapshot and patch ordering**: A subscriber joining mid-stream receives the initial snapshot, followed by precisely ordered patches with no gaps, guaranteeing array appends are never duplicated.
3. **Fencing**: A producer holding a superseded epoch is rejected immediately upon attempted write (`lease_conflict`).
4. **Base sequence check**: Updates with an out-of-date base sequence are rejected (`resync_required`) instead of guessing or blindly applying.
5. **Atomic patches**: Invalid operations anywhere in a patch reject the whole command (`invalid_state`), leaving the database unchanged and clean.

## Observations on the Hibernation API

- **What it preserves**: The Hibernation API preserves the WebSocket handles (reconnectable upon waking) and explicit tags/attachments on those sockets. 
- **What it does not preserve**: Any in-memory state on the Durable Object class instance (`this.foo`) is lost during eviction/hibernation. State must be reconstructed from SQLite or attached socket metadata upon waking.
- **Idle costs**: Keeping an idle room open incurs zero compute duration while the DO is hibernated. The DO shuts down and no longer bills CPU time. You only pay the standing connection fee and storage/invocation costs when a message arrives or an alarm fires to wake the object up.
