# Harness Map (behavior-to-test mapping)

Would the tests fail for the bugs this diff is most likely to introduce? Judge by regression value, not coverage percentage; skip trivial accessors.

**Tests already ran** — see `checks/summary.tsv`, the `go-test*` logs, and `checks/setup.txt`. A failing or timed-out test in a changed package is a finding, or an Open check when it's environmental (say why). Don't re-run the suite; one `go test -run` to prove a point is fine.

## Language lens

- **Go** — table-driven tests with named subtests; `errors.Is/As` on error paths; negative and validation cases; boundaries; cancellation and timeouts; transaction and store failures; HTTP request/response; converters across layers; strong-type parsing; race-sensitive code.
- **Vue/JS/TS** — rendering, `props`/`emits`, interactions, async and error states.
- **SQL / Rego / proto** — migration up/down, policy allow/deny cases, contract and codegen checks.
- No automated path to test a change? Say so and name the manual check.

## Patrol route

1. **Behaviors** (working notes, not reported): for each changed production symbol, its success, failure, boundary, state, and layer-crossing behavior.
2. **Match to tests** via `gopls` references or `rg` in test files; integration tests count when they truly exercise the behavior.
3. **Judge the tests.** Flag ones that assert implementation details, wouldn't catch a realistic regression, are too broad, or weaken assertions, skip, or mock around the real problem.

## Gates

- **G4** — critical behavior untested (auth, data integrity, money, persistence, validation, security), or a changed package's test fails for a code reason.
- **G3** — an important error path, boundary, converter, or business rule untested.
- **G2** — tests exist but are brittle, incomplete, or poorly named.
- **G1** — a small case, name, or assertion.

## Extra fields

- Untested behavior
- Regression it would catch
- Test sketch: Arrange / Act / Assert
