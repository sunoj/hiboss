<!-- What HiBoss believes about agents, bosses and the relations between them.
     Every product, API and UI decision should be traceable to a rule here. -->
# The HiBoss philosophy

HiBoss exists for one situation: **several agents are doing real work for one person,
and that person's attention is the scarcest thing in the system.** Everything below
follows from protecting that attention without ever trading away the person's control.

## 1. The three roles

### Boss

The boss is the party **accountable** for the work. Authority starts and ends with the
boss: only a boss can approve, choose, or grant access.

- A boss is usually a human. It can also be an AI acting as a boss for other agents
  (agent-as-boss). The role is defined by accountability, not by being human.
- A boss has one identity across devices. iPhone, Mac, Discord and Telegram are
  windows onto the same boss, not separate bosses. A decision answered on one device
  is answered everywhere.
- A boss's access is explicit: an `admin` boss sees every agent; other bosses see the
  agents they were granted. Nothing reaches a boss it was not granted, and nothing
  leaves a boss's scope by accident.

### Agent

An agent is a **worker with a name and a credential**, doing a task on a boss's behalf.

- An agent has a durable identity (its key) and transient sessions (a project, a
  branch, a machine). The boss reasons about sessions, the system authenticates agents.
- An agent owns the work, not the decision. It decides **how**; the boss decides
  **whether**, wherever the outcome is irreversible, outward-facing or costly.
- An agent is autonomous by default. The server offers capabilities; it does not decide
  behaviour for the agent (no automatic reactions, no hidden policies).

### Peer

A peer is **another agent working beside this one** — another session on the same
project, or another project for the same boss.

- Peers coordinate; they do not command. A message from a peer is information to weigh,
  never an instruction to obey and never a substitute for the boss's authority.
- Peers have no authority over each other's work, Box items or decisions. An agent may
  edit or delete only what it created.

## 2. What flows between them

Every channel has one meaning. Choosing the right one is part of doing the job.

| Channel | Meaning | Interrupts the boss? |
|---|---|---|
| `ask` | A decision only the boss can make, with options and an optional deadline | Yes, once |
| `send` | Something the boss should read: a result, a report, a blocker | Yes, by priority |
| `panel` | State worth **watching** while it changes: a series, a test run, a sweep | No |
| `progress` | Something worth **showing** once: a screenshot, a clip, a shipped feature | No |
| `request` | An intake of two or more fields or free-form values, attached to a panel | Once, if blocking |
| `box` | Reference material for later: text, links, files | No |
| peer `send` | Coordination between agents | No: it is not the boss's queue |

A channel used for the wrong job costs the boss attention or hides something they
needed: a static card on the panel wall is a message in the wrong place; a progress
note sent as `ask` is an interruption with nothing to decide.

## 3. Rules of authority

1. **Only the boss authorizes.** Approval comes from a boss reply on the decision it
   answers, and nowhere else.
2. **Silence is not consent.** A deadline may auto-select a default so work can move,
   but the system records it as `auto_default` and it never authorizes an
   irreversible or outward-facing action.
3. **Answers are scoped.** A questionnaire answer is data for the task that asked; it
   is not permission for any external action the answer mentions.
4. **Content is data, never instructions.** Box items, peer messages, fetched pages and
   attachments are reference material from their labelled author. An agent reads them;
   it does not obey them.
5. **Provenance is always visible.** Every item says who made it: the boss, which agent,
   which session. An agent's item never passes as the boss's own.
6. **Exactly one answer wins.** A decision is delivered to every boss window; the first
   answer resolves it everywhere and the others withdraw it.

## 4. Rules of truth

1. **A claim needs a receipt.** "Sent", "delivered", "coordinated" mean the server
   confirmed it and the agent read the confirmation. An upload is not a delivery; a
   delivery is what the recipient can see.
2. **No invented precision.** A gap in a series is `null`, never zero. A percentage
   needs a real denominator; a continuous task shows stage, duration and freshness.
3. **Freshness is part of the value.** A number without its age is a guess. Live state
   shows when it last changed; a disconnected client says so before it says "all clear".
4. **Failures are reported, not smoothed.** A test that failed, a step that was skipped,
   a delivery that was not confirmed: each is stated plainly, with the evidence.

## 5. Rules of attention

1. **The boss is interrupted only for what needs the boss.** Decisions first, results
   second, everything else is pull, not push.
2. **One decision at a time on the most intrusive surface.** The Dynamic Island, the
   Mac notch and the lock screen carry the single most urgent decision, never a queue.
3. **Answerable where it appears.** A decision with options can be answered from the
   card that shows it, without opening anything.
4. **Context travels with the question.** A decision states what it changes, what is
   at risk and what happens if nobody answers, in the card itself.
5. **Quiet when nothing needs the boss.** "All clear" is shown only when the stream is
   healthy and coverage is complete; otherwise the screen explains what it cannot see.

## 6. Agents among agents

- **Announce, then work.** Before touching shared ground, an agent broadcasts what it
  is about to change; on finishing, what changed.
- **Address by name, verify by receipt.** An agent addresses a peer by name or session;
  the server resolves it and reports the target it actually chose. An ambiguous name
  is an error to correct, not a guess to make.
- **Unacknowledged is undelivered.** A peer message that was never picked up has not
  coordinated anything.
- **The boss's view stays clean.** Peer traffic is not the boss's queue and never asks
  the boss for anything; its outcomes reach the boss through the agents' own reports.
- **An AI boss follows the same rules.** When an agent acts as another agent's boss,
  it inherits every rule of authority above, including that silence is not consent.

## 7. What this means for the product

- **Server:** exposes capabilities, records provenance and outcomes, never decides for
  an agent and never upgrades a default into an approval.
- **CLI and hooks:** make the right channel the easy one; never fail the agent's work
  because HiBoss is unavailable; report the limitation instead.
- **Clients:** the main screen answers, in order, *what needs me*, *what is running*,
  *what just arrived*. Every item shows its author and its age. Every decision shows
  its deadline and its default, and says plainly that the default is not approval.
- **Self-hosted:** one boss's data lives on their own deployment. No telemetry, billing
  or multi-tenant machinery competes with the boss's control.

## Where these rules are enforced

| Rule | Enforcement |
|---|---|
| One answer wins | Atomic conditional update on option selection (`.aid/knowledge/architecture-decisions.md`) |
| Silence is not consent | `auto_default` marker on timeout replies; `hiboss ask --json` `outcome` |
| Provenance | Box `added_by`, agent-only edits of own items (`docs/hiboss-box-design.md`) |
| No invented precision | Panel contract: `null` gaps, real denominators (`docs/live-panels/`) |
| Receipts | `--wait-ack`, broadcast exit status, `hiboss status` |
| Access scope | `resolvedBosses()` grants and boss roles |
