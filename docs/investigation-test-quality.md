KB consulted: behavioral negative controls and non-vacuous test assertions.

# Panel expiry test coverage

The former `server/src/panels/lifecycle/types.test.ts` checked three exported literal values.
The publication tests checked the default expiry and one explicit TTL of 120 seconds.
Those checks did not establish enforcement of the documented integer range, 60–604800 seconds.

| Check | Result | Evidence |
| --- | --- | --- |
| Existing tests reject a missing lower bound | FAIL | All three selected cases still passed |
| Existing tests reject a missing upper bound | FAIL | All three selected cases still passed |
| Existing tests reject a missing integer check | FAIL | All three selected cases still passed |
| Existing tests reject ignoring the explicit TTL when calculating expiry | FAIL | All three selected cases still passed |
| Replacement tests detect each fault independently | PASS | Each of the four isolated mutations failed the relevant cases |
| Unmodified production code passes the replacement and related tests | PASS | 47 cases across four files passed; none skipped |

The constant-only test was removed. The publication API now verifies the default TTL, both inclusive
bounds and an interior value against the stored expiry timestamp. Seven rejection cases cover values
below and above the range, a fractional number, a numeric string, a boolean, an array and an object.
Each rejection checks HTTP 422, the lifecycle error code, and the absence of a stored panel.
Expected values are literals independent of the implementation's constants.

Verification used commit `cb0aa4c627fee91999a8fcb6f4bf0d3e6c5cddb1`:

```sh
cd server
npm run typecheck
npx vitest run src/panels/definition/index.test.ts src/panels/lifecycle/recovery.e2e.test.ts \
  src/panels/relay/room.test.ts src/panels/relay/wall.e2e.test.ts
```

Type checking passed. Negative controls temporarily omitted each range/integer check, then replaced
the expiry calculation's explicit TTL with 3600. The old selected tests passed each mutation; the
corrected tests failed on 59, 604801, 60.5, and the three explicit TTL expiry timestamps respectively.
Every production source byte was restored before the final passing run.

Verdict: the TTL replacement passes. Repository-wide test quality remains unverified; a static
inventory or an absence of obvious assertion tautologies does not establish behavioral coverage.

## Guardrail workspace isolation

The CLI guardrail fixture formerly named directories with PID plus wall-clock nanoseconds. An
instrumented run of all three parallel tests recorded identical names in the help and example
validation tests. The help test removed their shared directory while example validation was active;
the latter then failed with a missing file and panicked again during cleanup. Two earlier attempts
passed, so a passing retry alone did not establish isolation.

`cli/tests/panel_guardrail.rs` now uses the existing counter-based `cli_ux_support::Sandbox`.
The help test checks that two live sandboxes have distinct paths, removes one, then exercises the
real CLI in the surviving sandbox. Successful tests explicitly check that their directory exists
before cleanup and is absent afterward. Cleanup assertions run outside the destructor.

A negative control replaced the shared allocator's counter value with zero. The peer-isolation
assertion failed as required. After restoring the helper, the complete CLI suite passed 539 tests
across 27 nonempty suites, with zero failures, ignored cases or filtered cases.

## Semantic enum coverage

The console's former semantic tests sampled one member per guard and one valid input per coercion.
They passed eight isolated faults: deleting a member from each of four enums, accepting normalized
spellings, accepting a prototype property name, and reducing either coercion to its single example.

`web/src/lib/design/semantics.test.ts` now checks all 17 guard members, malformed spellings, empty
strings and prototype property names. Both coercions check all valid members, missing values and
malformed inputs against independent literals. All eight faults fail the corrected checks.
After restoration, the console check reported zero errors or warnings and all 138 tests passed.

Both repairs were verified at `0fc9708fc8a0e8368985d36f15da8e3c6d41395e`, using `cargo test` in
`cli/`, `npm run check` in `web/`, and the complete Web Vitest run. Production code is unchanged.
These findings close the workspace-collision failure and the sampled enum coverage gaps; they do
not establish completion of the repository-wide review.

## Non-vacuous native ordering and the Home entry point

The shared and on-device text-ask ordering tests compared filtered results with a second call to the
same ranking implementation. Replacing the implementation's result with an empty array left both
tests passing. Both now require the independent order `auto`, `blocked`, `high`.

The Home/Live Activity agreement test formerly compared TodaySnapshot directly with the Live Activity
adapter, without traversing HomeAttentionSnapshot. Emptying the Home projection's groups left that
test passing. It now projects the ranked decisions through HomeAttentionSnapshot before comparing
the displayed order with Live Activity ranking, preserving the literal expected option order.

Three isolated controls verify these gaps: empty ranking results on macOS and iOS, and empty Home
groups on iOS. Each original selected test passes its fault; each corrected test fails it.
After restoring production source, verification at `3419ff41db138877fba99a40af107b39a862310a` passed
all 497 iOS unit tests, all 13 shared attention tests, and the macOS build. No cases were skipped.
All 24 case names and fixture inputs in the two edited files remain; only the expected vectors,
the Home projection call and the on-device test header changed. No production change was committed.
The platform tests are retained rather than removed solely because their fixtures overlap.

## Fixed-size rendering without content checks

The iOS JoinRequestRenderTests case rendered the approval sheet and request list in both appearances,
but only asserted that each image exceeded 600 points in height. Its renderer always used an
852-point window. Replacing either production view body with EmptyView left the case passing;
the corresponding exported images were visibly blank. The assertion did not establish page content.

The case and its private rendering, PNG export and service helpers were removed: 63 Swift lines,
plus four Xcode project references. Production views and SettingsNavigationUITests are unchanged.
The retained UI cases observe pushed verification details and approval, failed approval with the
code and Close action retained, and the empty request list explanation.

Each blank-view fault independently fails its existing UI case: the approval case cannot find
`join-request.code`, and the list case cannot find `No device requests`. After restoring the views,
verification at `266f653d517de5b8000207f22a313f98903e10e9` passes all 496 surviving iOS unit cases
and the three related UI cases, with zero failures or skips. The unit identities match the prior
497-case run minus exactly the reviewed renderer case. No additional test deletion is inferred.

## Routing-table ordering and state transitions

The routing tests sampled priority descending, known target names ascending and one toggle. The
case named for priority/enabled defaults never clicked enabled. All seven cases are retained, with
the priority case renamed for its expanded scalar-column matrix. They now check all five columns
in both directions, input preservation, missing target-name fallback, case-insensitive ID ties,
ten same-column toggle transitions and forty switches between columns and previous directions.

Nine independent faults pass the old selected suite and fail the corrected assertions: omitting
enabled's descending default, toggling only to ascending, substituting the channel/pattern/enabled
sort values, dropping unknown target IDs, sorting input in place, limiting ID ties to priority,
and using case-sensitive comparison. Production source is restored before final verification.

At `c0e0aff9a51cffb0ef8421b9b36118520cadef65`, all 138 Web tests pass and the console check reports
zero errors or warnings. Identities are compared by file path and full case name: two files contain
the same short-ID case name, so names alone are not unique. The final set matches the previous
138 cases with only the documented priority-case rename. No production code changed.

## Message-helper fixtures and boundary assertions

The original 109-case message-helper suite passed as a whole, but its channel listing case failed
in isolation because another test group prepared its rows. Query fixtures now initialize before the
query suite. Disabled and foreign channels, three recent outbound messages and excluded old/inbound
messages make channel filtering and the exact rate-limit boundary observable independently.

Seven isolated faults passed the original selected checks and fail the corrected assertions:
dropping an addressed row field, returning null for parsed reply metadata, writing session state
for a null session, changing the rate limit from inclusive to strict, including disabled channels,
reducing the valid option limit from five to four, and accepting only the first valid option member.
The corrected cases check populated fields, nonempty metadata, unchanged session data and both
sides of the numeric boundary. Option parsing also checks complete rejection errors and keyboards
compare complete nested results.

Row-preservation expectations use a frozen fixture and separate input copies. A control that
overwrites the input direction fails the original literal assertions, passes an intermediate
shared-object expectation, and fails the corrected independent expectation. That intermediate
expectation is not retained.

The 806-line suite is split by responsibility into five files totaling 728 lines, retaining all
109 case names. AST comparisons preserve all input/oracle vectors in 33 table cases and the bodies
of 37 cases; two cases occur in both comparisons. Verification at
`28e1fd562c2f8d0a4467de91b3fb36b32be77bcd` passes type checking and all 109 cases across four test
files, with zero failed, skipped or filtered cases. The previously dependent case also passes alone.
Every temporary production mutation is restored before the final run; production source is unchanged.

## Checked JSON reads and a nonempty routing list

Shared `testJson` checks the caller's exact expected status before consuming JSON. Its response
shape accepts both synchronous responses and promises, returns unknown JSON, and propagates request
and parse failures. It supplies no authorization, content-type or success-status defaults.
The 111 extracted reads in 50 test files retain their request expressions, result casts, comments,
hooks and subsequent assertions. Reversing the recorded edits reproduces every original caller byte;
AST comparison verifies each extraction, including literal and template contents.

Six calibration cases check expected 200/201/422 responses, unexpected status before body use,
malformed JSON and request-error identity. Removing the status check, reading the body first and
swallowing request failures each independently fail the intended calibration case.

The routing-list case formerly only checked that a result was an array. A router that always
returned an empty array passed it. The corrected case retains the initial array check, creates a
rule through the API, requires the returned list to contain its ID and supplied fields, and deletes
the fixture in finally. Expected fields are frozen independently of the returned representation.
The empty-list fault now fails this case; the other six routing cases retain their names and checks.

At `0d198571bd09d8754430e9c3cde4d5cb5bf3e8d7`, type checking and all 876 cases across the 83
test files importing the shared module pass, with zero failures, skipped or filtered cases.
The complete scoped run occurs after all temporary helper and router faults are restored.
Including six new calibration cases and the routing repair, this change removes 100 source lines.
