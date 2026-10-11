KB consulted: the startup and coverage search returned simulator launch-environment
handling guidance, but no matching PanelsModel publication defect.

# Native Today startup coverage

## Coverage publication

PanelsModel publishes relay state, live subscription membership, wall connectivity,
and fetch progress. The final tile snapshot can therefore redraw Today immediately,
even if visible tile IDs and pending questionnaire counts have not changed. Clock
publication is not required for coverage changes. HTTP checkpoints remain insufficient
for running server-backed tiles: a received relay frame is still required.

## Startup ordering

The iOS connected-services root owns the panel model and starts it alongside history
and required inputs. Tab appearance is no longer the trigger. Independent panel-list
and questionnaire reads overlap, while revision-dependent tile details retain their
existing bounded concurrency. Changing accounts replaces the panel model.

An overlapping load does not invalidate a current load. Actual metadata changes,
wall change notifications, disconnections, and account changes still revoke stale
questionnaire coverage and coalesce a follow-up reconciliation. Foreground history
refreshes also reuse in-flight history and required-input work; explicit refreshes
remain available.

## Readiness barriers

The first wall.changed frame acknowledges subscription. It is delivered only to the
connection callback, rather than also being treated as a metadata invalidation.
Acknowledgement during a load preserves its generation and fetched tile stores.

The wall protocol carries no replay cursor. Reads started before acknowledgement
are therefore revalidated after it, retaining unchanged tile definitions, stores,
and live subscriptions. If a load has already finished while disconnected, the
acknowledgement schedules reconciliation. Acknowledgement alone never authorizes
questionnaire completeness.

Required-input ready follows an initial complete stream scan, but has no shared
watermark with HTTP. In particular, an initial empty scan sends no resolved event
for an obsolete row from an earlier HTTP snapshot. The post-ready HTTP reconciliation
is retained to remove such rows. Coverage still requires ready plus a successful
current snapshot, and all watchdog deadlines are unchanged.

## Timing evidence

Startup logs use subsystem ai.hiboss.app and category startup. Elapsed milliseconds
are anchored to kernel process creation time with a monotonic uptime clock. Logs
contain static state names and counts only. No disk history cache is used.

The simulator measurement script runs a demo with 1,200 ms history, required-input,
panel-list, and questionnaire delays, and a 300 ms required-input readiness delay.
The demo has no server relay, so it measures startup scheduling rather than production
socket latency. Relay coverage rules are exercised separately by held-service and relay-frame
regression tests.
