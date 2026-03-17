# hiboss Layer 3: Cross-Session Agent Communication

## Research Summary

### Industry Landscape (2024-2025)

| Framework/Protocol | Model | Key Insight for hiboss |
|---|---|---|
| **Google A2A** | Agent Card discovery + task lifecycle (submitted→working→completed) via JSON-RPC + SSE | Agent registration + task state machine |
| **OpenAI Swarm** | Stateless handoff via function returns, context_variables dict | Lightweight context passing, no heavy abstractions |
| **CrewAI** | Role-based agents (Researcher, Developer, Reviewer) with YAML configs | Role conventions, structured pipelines |
| **AutoGen** | Conversational group chat, event-driven | Dynamic debugging via "debate" pattern |
| **Claude Code Teams** | Lead + teammates, shared task list, `sendMessage` tool, 2-5 optimal | Closest to our use case, peer messaging |
| **LACP (arxiv)** | 3-layer: Semantic + Transaction + Security | Idempotency, intent clarity |
| **ALMAS (arxiv)** | Agile roles: Sprint Planner, Developer, Reviewer | SDLC-aligned role taxonomy |

### Academic Findings

- **Agent "social tools"** (journaling, internal messaging) make agents **12-38% faster** on complex tasks (arxiv:2509.13547)
- **Croto**: Multiple teams exploring different solutions outperform single-team approaches (arxiv:2406.08979)
- **MacNet**: DAG-based orchestration scales to 1000s of agents but adds complexity

### Production Realities

| Metric | Finding | Implication |
|---|---|---|
| **Coordination tax** | Up to 26x cost increase if unmanaged | Keep protocol minimal |
| **Token inflation** | 15-35x more tokens vs single agent | Compress context, avoid verbose handoffs |
| **Error amplification** | 17.2x in unstructured networks | Structured task states, clear boundaries |
| **Optimal team size** | 2-5 agents, plateaus after 5 | Don't design for 100 agents |
| **20% rule** | Coordination overhead > 20% of tokens = inefficient | Measure and cap overhead |

## Design Philosophy

**hiboss is a communication layer, not a workflow engine.**

Lessons from the research:
1. **Swarm over AutoGen**: Lightweight beats heavy. No "group chat" abstraction — just targeted messages.
2. **A2A Agent Card**: Discovery via self-description, not central registry.
3. **CrewAI roles**: Conventions, not enforcement. Roles label intent, not restrict capabilities.
4. **Claude Code Teams**: Shared task list is powerful. Peer-to-peer messaging beats hub-and-spoke.
5. **Production data**: Minimize coordination tokens. Context compression is critical.

## Architecture

```
                    hiboss server (D1 + Hono)
                           │
            ┌──────────────┼──────────────┐
            │              │              │
      CC Session A    CC Session B    CC Session C
      (orchestrator)  (worker)        (reviewer)
            │              │              │
         agent-a        agent-b        agent-c
            │              │              │
            └──── messages table ─────────┘
                  + target_agent_id
                  + task_id
                  + task_state
```

No new infrastructure. Reuse existing D1 messages table with 3 new columns.

## Detailed Design

### 1. Session Discovery (Agent Card)

Inspired by A2A's Agent Card — each session announces itself on startup.

**DB: Extend `api_keys` table**

```sql
ALTER TABLE api_keys ADD COLUMN role TEXT;           -- orchestrator | worker | reviewer | NULL
ALTER TABLE api_keys ADD COLUMN session_info TEXT;   -- JSON agent card
```

**Agent Card format** (stored in `session_info`):

```json
{
  "project_dir": "/Users/ming/project-x",
  "git_branch": "feat/oauth",
  "capabilities": ["rust", "typescript", "testing"],
  "started_at": "2025-03-17T10:00:00Z"
}
```

**API**:
- `PUT /api/agents/me/config` — already exists, extend to accept `role` + `session_info`
- `GET /api/agents` — already exists, extend response to include `role` + `session_info`

**CLI**:
```bash
# Auto-registered by SessionStart hook:
hiboss agent config --role worker --session-info '{"project_dir":"'$(pwd)'","git_branch":"'$(git branch --show-current)'"}'

# Discovery:
hiboss agent list
#  NAME           ROLE          STATUS   BRANCH        PROJECT
#  auth-worker    worker        online   feat/oauth    /path/to/repo
#  test-runner    worker        idle     main          /path/to/repo
#  lead           orchestrator  online   main          /path/to/repo
```

**Why this over A2A's `/.well-known/agent.json`**: Our agents are all on the same server. No need for HTTP-based discovery — a DB column suffices. If we ever need cross-server federation, we can add Agent Card HTTP endpoints later.

### 2. Agent-to-Agent Messaging

The core addition. One agent sends directly to another agent's inbox.

**DB: Extend `messages` table**

```sql
ALTER TABLE messages ADD COLUMN target_agent_id TEXT;  -- NULL = boss message (backward compat)
```

**Direction semantics**:

| direction | target_agent_id | Meaning |
|---|---|---|
| `agent_to_boss` | NULL | Agent → human boss (existing) |
| `boss_to_agent` | NULL | Human boss → agent (existing) |
| `agent_to_agent` | set | Agent A → Agent B (new) |

**API: Extend `POST /api/messages`**

```json
{
  "body": "Implement OAuth2 login flow",
  "to": "auth-worker",           // NEW: target agent name or ID
  "priority": "normal",
  "options": ["Done", "Blocked"],
  "metadata": {
    "task_context": { ... }      // structured context (see §3)
  }
}
```

Server behavior:
- Resolve `to` → `target_agent_id` (by name or ID prefix)
- Set `direction = agent_to_agent`
- Deliver to target's configured channels (same delivery logic as boss messages)
- If target has callback URL, notify via webhook

**API: Extend `GET /api/messages`**

```
GET /api/messages?unread=true
```

Now returns BOTH `boss_to_agent` AND `agent_to_agent` (where target = self) messages.

New filter:
```
GET /api/messages?from=lead-agent    // filter by sender
```

**CLI**:
```bash
# Send to another agent
hiboss send --to auth-worker "Implement OAuth2 login flow"

# Ask with options (blocking)
hiboss ask --to auth-worker --options "Done,Blocked" "Implement OAuth2"

# Inbox shows all incoming (boss + agent)
hiboss inbox
#  [agent] lead → you: "Implement OAuth2 login flow"  (2m ago)
#  [boss]  Ming → you: "Check the deploy logs"         (5m ago)

# Filter by sender
hiboss inbox --from lead-agent
```

**Hook changes**:
- SessionStart: Show `agent_to_agent` messages alongside `boss_to_agent`
- PostToolUse: Check for urgent agent messages too
- Display format distinguishes boss vs agent origin

### 3. Context Passing (Task Bundle)

The hardest problem. Research shows context compression is critical (15-35x token inflation risk).

**Approach**: Structured metadata, not a new table. Keep it in the message `metadata` field.

**Task context schema**:

```json
{
  "task_context": {
    "summary": "Implement OAuth2 login with Google provider",
    "files": ["src/auth/oauth.ts", "src/types.ts"],
    "branch": "feat/oauth",
    "constraints": ["No external deps beyond existing", "Must pass CI"],
    "expected_output": "Working OAuth2 flow with tests",
    "parent_task_id": "msg-abc123"
  }
}
```

**CLI shorthand**:

```bash
hiboss send --to worker-1 \
  --task "Implement OAuth2 login" \
  --files "src/auth/,src/types.ts" \
  --branch feat/oauth \
  "No external deps. Must pass CI."
```

The `--task` flag wraps into `metadata.task_context.summary`, `--files` into `metadata.task_context.files`, `--branch` into `metadata.task_context.branch`. Message body becomes `constraints`.

**Receiving side hook display**:

```
📨 Task from lead-agent:
   Summary: Implement OAuth2 login
   Files: src/auth/, src/types.ts
   Branch: feat/oauth
   Constraints: No external deps. Must pass CI.
   Reply with: hiboss reply <id> "status update"
```

**Why not file attachments for context?** Too heavy. File paths + git branch is enough — the receiving CC session has full file system access. The research shows compressed context beats verbose dumps.

### 4. Task Lifecycle (Lightweight)

Inspired by A2A's task states but much simpler. No separate tasks table — task state lives on message threads.

**Task states** (tracked via reply chain):

```
assigned  →  accepted  →  working  →  completed
                 ↓            ↓
              rejected     blocked → input-required → working → completed
```

**Implementation**: The original message is the "task". Replies update the state. Convention-based, not server-enforced.

```bash
# Orchestrator assigns
hiboss send --to worker "Implement feature X"

# Worker accepts
hiboss reply <id> --status accepted "Starting now"

# Worker reports progress
hiboss reply <id> --status working "50% done, auth module complete"

# Worker completes
hiboss reply <id> --status completed "Done. PR: feat/x, all tests pass"

# OR: Worker is blocked
hiboss ask --to lead --reply-to <id> --status blocked \
  --options "Option A,Option B" "Blocked on DB schema decision"
```

The `--status` flag sets `metadata.task_status` on the reply. The orchestrator can query:

```bash
# List tasks by status
hiboss inbox --status working    # all active tasks
hiboss inbox --status blocked    # things needing attention
```

**Server: Minimal support**

```sql
-- No new table. Query via metadata:
SELECT * FROM messages
WHERE target_agent_id = ?
  AND json_extract(metadata, '$.task_context') IS NOT NULL
  AND json_extract(metadata, '$.task_status') = 'working'
```

Optional: Add an index on `target_agent_id` for performance.

**Why no separate tasks table?** The message IS the task. Adding a tasks table duplicates state and creates sync problems. Keep it simple — a task is a message thread with status metadata.

### 5. Role Conventions

Soft labels, not hard enforcement. Inspired by CrewAI roles + ALMAS Agile mapping.

| Role | Typical actions | Sends to | Receives from |
|---|---|---|---|
| `orchestrator` | Decompose, assign, review, decide | workers, reviewers | completion reports, review verdicts |
| `worker` | Implement, test, report | orchestrator (status) | task assignments |
| `reviewer` | Review code, approve/reject | orchestrator (verdicts) | review requests |

**No server enforcement.** Any agent can message any agent. Roles help with:
- Discovery: `hiboss agent list --role worker`
- Hook display: Show role context in inbox messages
- Future: Auto-routing to available workers

### 6. Orchestration Patterns

Based on research, three patterns emerge for hiboss cross-session:

#### Pattern A: Hub-and-Spoke (Recommended Default)

```
         Orchestrator
        /     |     \
   Worker1  Worker2  Reviewer
```

One CC session acts as orchestrator, others as workers. The orchestrator:
1. Decomposes work into tasks
2. Assigns to workers via `hiboss send --to`
3. Monitors progress via `hiboss inbox --status working`
4. Routes completed work to reviewer via `hiboss send --to reviewer`

This matches how `aid` works today, but across CC sessions instead of lightweight agents.

#### Pattern B: Pipeline

```
   Planner → Implementer → Tester → Reviewer
```

Each stage hands off to the next. The `--actions` feature enables this:

```bash
# Implementer finishes, triggers tester
hiboss ask --to reviewer \
  --actions "Approved:hiboss send --to tester 'Start testing feat/x',Rejected:hiboss send --to implementer 'Rework needed'" \
  "Review feat/x branch"
```

#### Pattern C: Peer Mesh (Advanced)

```
   Agent A ←→ Agent B
      ↑  ↘  ↗  ↓
       Agent C
```

No central orchestrator. Agents coordinate directly. Useful for:
- Debugging (multiple investigators)
- Croto-style parallel exploration

**Risk**: Error amplification (17.2x). Only use with experienced human oversight.

## Migration Plan

### Phase 1: Core Messaging (v0.11)

**Server**:
```sql
-- Migration 0008_agent_messaging.sql
ALTER TABLE messages ADD COLUMN target_agent_id TEXT;
ALTER TABLE api_keys ADD COLUMN role TEXT;
ALTER TABLE api_keys ADD COLUMN session_info TEXT;
CREATE INDEX idx_messages_target ON messages(target_agent_id);
```

- Extend `POST /api/messages` to accept `to` field
- Extend `GET /api/messages` to include `agent_to_agent` in unread queries
- Extend `GET /api/agents` to return role + session_info
- Extend `PUT /api/agents/me/config` to accept role + session_info
- Deliver agent_to_agent messages via target's configured channels

**CLI**:
- `hiboss send --to <agent>` — target another agent
- `hiboss ask --to <agent>` — blocking ask to another agent
- `hiboss inbox` — show both boss and agent messages (with origin label)
- `hiboss inbox --from <agent>` — filter by sender
- `hiboss agent config --role <role>` — set role
- `hiboss agent list` — show role column

**Hooks**:
- SessionStart: Auto-register session_info (cwd, git branch)
- SessionStart: Show agent_to_agent messages in inbox
- PostToolUse: Check for urgent agent_to_agent messages

### Phase 2: Task Context (v0.11.1)

**CLI**:
- `--task`, `--files`, `--branch` flags on `hiboss send`
- `--status` flag on `hiboss reply`
- `hiboss inbox --status <state>` filter

**Hooks**:
- Format task context in SessionStart display
- Display task status updates distinctly

### Phase 3: Workflow Patterns (v0.12)

- `hiboss workflow` commands for defining pipelines
- Auto-registration of role + capabilities on session start
- `hiboss agent list --role worker --status online` for discovery
- Template workflows (code-review, feature-dev, investigation)

## What NOT to Build

Based on production data showing coordination overhead risks:

1. **No agent spawning** — Orchestrator doesn't create CC sessions. Human starts them.
2. **No workflow engine** — No server-side DAG execution. Agents coordinate via messages.
3. **No group chat** — AutoGen-style multi-agent conversation is token-expensive. Use targeted messages.
4. **No shared memory** — Each session has its own context. Pass what's needed, not everything.
5. **No consensus protocol** — No voting, no quorum. One orchestrator decides.
6. **No automatic retry** — If a task fails, the orchestrator decides next steps. No server-side retry logic.

## Example: Full Workflow

```bash
# Terminal 1: Human starts orchestrator
claude  # CC session starts
> # SessionStart hook registers: role=orchestrator, branch=main

# Terminal 2: Human starts worker
claude  # CC session starts
> # SessionStart hook registers: role=worker, branch=feat/oauth

# Terminal 3: Human starts reviewer
claude  # CC session starts
> # SessionStart hook registers: role=reviewer, branch=main

# --- In Terminal 1 (orchestrator) ---
> hiboss agent list
#  NAME        ROLE          STATUS   BRANCH
#  lead        orchestrator  online   main
#  dev-1       worker        online   feat/oauth
#  reviewer-1  reviewer      online   main

> hiboss send --to dev-1 --task "Implement OAuth2 login" \
    --files "src/auth/,src/types.ts" --branch feat/oauth \
    "Use Google provider. Must pass existing tests."

> # Orchestrator continues other work...
> hiboss inbox --status working   # check active tasks

# --- In Terminal 2 (worker dev-1) ---
> # SessionStart hook shows:
#   📨 Task from lead:
#      Summary: Implement OAuth2 login
#      Files: src/auth/, src/types.ts
#      Branch: feat/oauth
#
> hiboss reply <id> --status accepted "Starting implementation"
> # ... worker implements the feature ...
> hiboss reply <id> --status completed "Done. All tests pass. Ready for review."

# --- In Terminal 1 (orchestrator sees completion) ---
> # PostToolUse hook: "dev-1 completed task: Implement OAuth2 login"
> hiboss send --to reviewer-1 --task "Review OAuth2 implementation" \
    --branch feat/oauth "Check src/auth/ changes. Verify test coverage."

# --- In Terminal 3 (reviewer) ---
> # SessionStart hook shows review request
> hiboss reply <id> --status completed "Approved. Clean implementation, good test coverage."

# --- In Terminal 1 (orchestrator) ---
> # Merges the branch, assigns next task
```

## Cost Estimate

Based on the 20% rule:
- A task assignment message: ~200 tokens (body + metadata)
- A status update reply: ~100 tokens
- A full task lifecycle (assign + accept + 2 updates + complete + review): ~800 tokens
- Overhead vs. a 50K token coding task: **1.6%** — well under the 20% threshold

hiboss's message-based approach is inherently token-efficient because it passes structured metadata, not full conversation history.

## References

1. Google A2A Protocol — https://a2a-protocol.org
2. OpenAI Swarm — https://github.com/openai/swarm
3. CrewAI — https://www.crewai.com
4. LACP — arxiv:2510.13821
5. ALMAS — arxiv:2510.03463
6. AgentMesh — arxiv:2507.19902
7. Social tools for agents — arxiv:2509.13547
8. Croto (cross-team orchestration) — arxiv:2406.08979
9. Claude Code Team Mode — Anthropic documentation
