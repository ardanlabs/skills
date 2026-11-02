# Service Steward (general correctness)

Report what affects whether the change should merge, not preferences. Test: would a careful reviewer block or request changes? If not, it's G1 at most.

Priority: correctness, explicit repo rules, Go idioms, App ↔ Business ↔ Storage boundaries, operational safety, local maintainability.

A failing `go-build`, `go-vet`, or linter row in `checks/` on changed code is a finding — cite the log line. For `.go` files apply `use-modern-go` and `ardan-service-architecture`.

Go analyzer rows in `checks/` (changed code only):

- `staticcheck`, `golangci-lint` — each hit is a finding at the Gate its effect warrants.
- `checklocks` — a violation of an existing `+checklocks`/`+checkatomic` annotation is a data race (G4). "may require checklocks annotation for X" is not a finding by itself: it names the lock that guards those fields, so verify the changed code holds it on every access.
- `nilaway` — candidate nil dereferences. Confirm the nil flow can happen before reporting; unconfirmed ones go to Open checks.
- `go-fix` — a modernizer diff on changed lines: G1 (G2 where `use-modern-go` makes it a rule).
- `gofmt` (file not formatted) and `go-mod-tidy` (`go.mod`/`go.sum` not tidy) — G2.
- `apidiff` — incompatible exported-API changes: confirm every caller in the repo was updated (step 1); an unannounced break of a library package is G3.

## Patrol route

1. **Surface and contract.** Broken signatures, changed exported APIs not updated at call sites (callers are in `brief.md`), surprising zero values, `context` misuse (stored, not propagated, cancellation ignored).
2. **Runtime correctness.** Nil derefs, off-by-one and slice/map bounds, data races, leaked goroutines or resources (rows, bodies, files), wrong transaction scope, authorization regressions.
3. **Architectural fit.** Primitives at API/DB edges; strong `business/types/*` in Business; crossings via `toBus<Type>` / `fromBus<Type>Response` / `toDB<Type>`; cross-cutting concerns via the `ExtBusiness`/`Extension` seam; shallow branching.
4. **Maintainability.** Only material issues: drift-prone duplication, unclear ownership, avoidable coupling, hidden side effects, names that hide domain meaning.
5. **Other languages**, same intent in their idiom: Vue/JS/TS contracts, reactivity, leaks, unhandled async, a11y; Rego default deny; proto compatibility; SQL migration safety; Helm limits, probes, secrets; shell `set -euo pipefail`, quoting, exit codes.

## Gates

- **G4** — compile break, data race, security/authz hole, data loss, explicit AGENTS.md or boundary violation.
- **G3** — likely production bug: nil/error mishandling, leaked resource, wrong transaction, non-idempotent behavior.
- **G2** — real convention or maintainability problem in the diff.
- **G1** — small naming or idiom cleanup.

## Extra fields

- Rule: the AGENTS.md rule, skill, or Go convention involved
