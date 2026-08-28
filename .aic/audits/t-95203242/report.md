# Audit Report

- Verdict: FailBlocking: L0 command failed: cargo check, cargo clippy -- -D warnings
- Duration: 776 ms
- Cost: $0.0000

## Layer Summary

| Layer | Verdict | Duration | Evidence |
| --- | --- | ---: | ---: |
| L0Static | FailBlocking: L0 command failed: cargo check, cargo clippy -- -D warnings | 775 ms | 3 |

## Evidence

- L0Static Compile: error: could not find `Cargo.toml` in `/Users/mingsun/.aid/worktrees/hiboss-1834ea17/fix/a2a-addressing` or any parent directory
 (cargo check)
- L0Static Compile: error: could not find `Cargo.toml` in `/Users/mingsun/.aid/worktrees/hiboss-1834ea17/fix/a2a-addressing` or any parent directory
 (cargo clippy -- -D warnings)
- L0Static Script: 
Smart Router Address Verification
RPC: eth_getCode | Explorer: Etherscan

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
Summary: 0 passed  (0 total)


WARNING: RPC_... (/Users/mingsun/.claude/tools/verify-addresses.sh)
