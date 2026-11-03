# Harness Map (behavior-to-test mapping)

Would the tests fail for the bugs this diff is most likely to introduce (at full depth, the bugs most likely in the code in scope)? Judge by regression value, not coverage percentage; skip trivial accessors. Use the **Tests** section of each idiom file in your prompt.

**Tests ran only for a maintainer PR** (`trust=maintainer`); otherwise their rows say "runs the reviewed code" and you judge the tests by reading them — don't report that they didn't run. When they ran, see the `lens=harness-map` rows of `checks/summary.tsv` (`go-test*`, `cargo-test*`, `pytest*`, approved `x-*` test gates) and `checks/setup.txt`. A failing or timed-out test is a finding when the change can cause it (at full depth, any test in a reviewed unit), or an Open check when it's environmental (say why). At `diff` depth, a failure unrelated to the change is out of scope: drop it. Don't re-run the suite; one targeted test run to prove a point is fine.

For infrastructure and pipelines, tests include policy tests, `terraform test`, chart unit tests, Molecule, and render/validate checks. When the change has no automated path to test it, say so and name the manual check.

## Patrol route

1. **Behaviors** (working notes, not reported): for each changed production symbol, resource, template, or task (at full depth, each in-scope one), its success, failure, boundary, state, and boundary-crossing behavior.
2. **Match to tests** via the language tool or `rg` in test files; integration tests count when they truly exercise the behavior.
3. **Judge the tests.** Flag ones that assert implementation details, wouldn't catch a realistic regression, are too broad, or weaken assertions, skip, or mock around the real problem.

## Gates

- **G4** — critical behavior untested (auth, data integrity, money, persistence, validation, security, destructive infrastructure change), or an in-scope test fails for a code reason.
- **G3** — an important error path, boundary, converter, business rule, or policy untested.
- **G2** — tests exist but are brittle, incomplete, or poorly named.
- **G1** — a small case, name, or assertion.

## Extra fields

- Untested behavior
- Regression it would catch
- Test sketch: Arrange / Act / Assert
