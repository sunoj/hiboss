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
