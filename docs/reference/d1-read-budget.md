# D1 read budget

D1 bills rows read. That count includes the index entries and rows a statement visits, not
only the rows it returns. A statement that runs on a timer, or that clients poll, therefore costs
its visited rows times its call rate. The server enforces a per-call rows-read budget for every
such path in the normal test suite. A script checks production totals once a day.

## The gate (`server/src/read-budget/`)

| File | Role |
|---|---|
| `meter.ts` | D1 proxy recording `meta.rows_read` per statement; `first()`/`raw()` are metered through `all()` |
| `seed.ts` | Production-shaped fixture: 16 agents (two busy, a long tail), 200 sessions, a small live set, and history layers of ~16 k messages, 8 k session events and 150 finished panels each |
| `drive.ts` | Drives a stream route for its connect phase plus 5 idle polls, an endpoint 3 times, or a cron step twice |
| `read-paths.ts` | Registry of repeated read paths, each with a per-call budget |
| `repeat-sites.ts` | Registry of every timed loop, interval and Durable Object alarm in `server/src` |
| `read-budget.test.ts` | Measures every path at N (one history layer) and 2N (two layers) |
| `server/scripts/poll-loops.check.ts` | Static completeness check (Node vitest config, part of `npm test`) |

`read-budget.test.ts` fails when:

- one call reads more than the path's `budget` (or the connect phase more than `connectBudget`);
- a call reads more than 25 rows more at 2N than at N, so its cost grows with history. A path
  whose cost necessarily tracks a table carries an `exemption` with a ceiling and a reason;
- a loop in `repeat-sites.ts` has no read path.

Streams run through their HTTP routes with the injected 25 ms poll interval. The meter
therefore counts authentication, the access check and the per-chunk credential recheck as well.
A call is one poll, grouped by the idle gap between statements.

### Registering a path

A new timed loop, alarm or interval, or a changed query inside one, updates both registries:

1. Add the site id printed by `poll-loops.check.ts` (`<path under src>#<function>`) to
   `repeat-sites.ts`. Give it the read paths that meter it, or an `unmetered` reason (for
   example, a loop with no D1 statement).
2. Add or update the read path in `read-paths.ts`. Set the budget from the measured N/2N numbers
   in the `READ_BUDGET` lines of the test output.

An endpoint path may also set `statementBudget`, the most D1 statements one request may issue
(waitUntil work included). It catches a per-row lookup (N + 1), which reads few rows per
statement but costs one round trip each.

A hot client-polled endpoint or a new cron step gets a read path the same way. Rank endpoints by
`wrangler d1 insights hiboss-db --sort-by count`.

### Registered paths (rows read per call; N ≈ 16 k, 2N ≈ 32 k messages)

| Path | Kind | Connect N / 2N | Per call N / 2N | Budget (connect) |
|---|---|---|---|---|
| `agent-stream` | loop | 5 / 5 | 3 / 3 | 20 (30) |
| `agent-session-stream` | loop | 8 / 8 | 5 / 5 | 20 (30) |
| `agent-reply-long-poll` | loop | 12 / 12 | 4 / 4 | 20 (30) |
| `boss-message-stream` | loop | 207 / 70 | 41 / 41 | 100 (300) |
| `boss-option-stream` | loop | 124 / 124 | 40 / 40 | 100 (300) |
| `boss-feed-stream` | loop | 241 / 99 | 98 / 70 | 150 (300) |
| `boss-required-input-stream` | loop | 269 / 269 | 88 / 103 | 150 (400) |
| `session-event-stream` | loop | 26 / 26 | 2 / 2 | 20 (60) |
| `panels-list` | endpoint, ≤ 6 statements | — | 157 / 157 | 300 |
| `message-detail-by-prefix` | endpoint | — | 31 / 31 | 100 |
| `sessions-delta` | endpoint, ≤ 8 statements | — | 62 / 62 | 100 |
| `interaction-requests` | endpoint | — | 14 / 14 | 100 |
| `cron-every-5-min` | cron | — | 9 / 9 | 100 |
| `cron-hourly` | cron, exempt | — | 8,038 / 16,043 | ceiling 25,000 |

The N measurements run first, so the N connect and the first polls also read the live rows that
the fixture inserted moments earlier. `cron-hourly` adds the abandoned-ask sweep. It runs 24 times
a day and visits every open `agent_to_boss` row without a deadline; its ask predicate is JSON,
so no plain index narrows it.

### Repeat sites and what the scan detects

`poll-loops.ts` parses each production source under `server/src` (tests and test support
excluded) with the TypeScript compiler API. It reports:

- **loop**: a `while`, `do`, `for`, `for…of` or `for…in` whose body or condition awaits a sleep.
  A sleep is `setTimeout` settling a `new Promise` (`new Promise((r) => setTimeout(r, ms))`),
  `setTimeout(ms)` from timers/promises, `scheduler.wait`, `delay`/`sleep`, or any loop-free
  function that wraps one of those (resolved by name across files);
- **interval**: `setInterval`;
- **alarm**: `setAlarm` (a Durable Object that re-arms itself);
- **reschedule**: a `setTimeout` whose callback names the enclosing function.

A `setTimeout` that rejects or aborts (a timeout guard) is not a sleep. A loop without a sleep
(pagination, batching) runs per request or per cron run; the endpoint and cron read paths
cover those. The scan does not see:

- a sleep passed in as a value (a parameter or callback);
- a sleep helper imported under a renamed alias that is not defined in `server/src`;
- `await setTimeout(ms)` where the argument is a bare identifier;
- loops driven by events (WebSocket messages, queue consumers);
- request rates chosen by clients. A client that polls an endpoint shows up only in
  `d1 insights --sort-by count`, which the production detector reads.

Classification of the repeat-capable files outside the stream routes:

| File | Classification |
|---|---|
| `routes/messages.ts` | `POST /:id/poll` is a loop (long-poll, 1 s production interval); registered as `agent-reply-long-poll` |
| `routes/message-helpers.ts` | Defines `delay`; no loop of its own |
| `routes/delivery.ts` | `deliverWithRetry` is a bounded retry (at most 2 attempts) of one outbound send per message; unmetered |
| `panels/relay/` | Retry alarms are armed only while a control operation is pending; wall expiry fires once per panel expiry; both read by primary key |
| `scheduled.ts`, `panels/lifecycle/repair.ts` | Cron steps (every 5 min, hourly sweep in minutes 0–4); registered as `cron-every-5-min` and `cron-hourly` |

## Production detector (`server/scripts/d1-read-watch.mjs`)

```bash
cd server && node scripts/d1-read-watch.mjs
```

It runs `wrangler d1 insights hiboss-db --time-period 1d --limit 100 --json` with both
`--sort-by reads` and `--sort-by count`, and merges the two lists by statement. It alerts through
`hiboss send --priority high` and exits non-zero when:

| Rule | Threshold (per day) |
|---|---|
| Total rows read over the listed statements | > 250,000,000 |
| One statement's rows read | > 50,000,000 |
| One statement averaging more than 2,000 rows read and running more than 5,000 times (a scan on a hot path) | — |

Exit 0 prints one line (`d1-read-watch: ok …`). Exit 1 is a breach. Exit 2 means the insights
could not be read; that case also sends an alert. `WRANGLER` and `HIBOSS` override the two
commands (the node test stubs both); `D1_DATABASE` overrides the database name. The total is a
lower bound: insights returns at most the listed statements.

Derivation, from the budgets above and the observed one-day run counts:

- The included allowance is 25 B rows a month, ≈ 806 M a day.
- At the measured per-call costs and the observed run counts, a day projects to ≈ 63 M rows
  (`scripts/fixtures/d1-insights-healthy-1d.json`). The total threshold is ≈ 4× that and
  ≈ 31 % of the daily allowance, so an alert leaves most of the month's allowance unused.
- The largest single statement in the healthy projection is the sessions list at ≈ 16 M a day.
  The per-statement threshold is about 3× that.
- One client on a 3 s poll runs a statement 28,800 times a day. Every registered poll reads at
  most 150 rows per call. A statement above 2,000 rows and 5,000 runs a day is therefore a
  scan on a hot path, even while the daily total is still small.
- `scripts/fixtures/d1-insights-scan-1d.json` holds a day of full-scan polls (1.31 B rows; one
  statement 803 M at 13.5 k rows × 59 k runs). It trips all three rules.
