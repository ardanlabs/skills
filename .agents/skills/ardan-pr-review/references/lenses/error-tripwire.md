# Error Tripwire (failure-path visibility)

Follow every changed failure path to its end and ask: when this fails, who finds out, and is that enough to debug it? Catch zero values returned after errors, log-and-continue, and success reported after partial failure. Vet and linter output in `checks/` flags unchecked errors mechanically — start there, then go further.

## Idioms

- **Go** — errors checked, wrapped with `%w`, matched with `errors.Is/As`, not `_`-discarded when they matter; `defer` cleanup failures handled; goroutines can report failure.
- **Vue/JS/TS** — promises and `await` caught; non-2xx handled; `catch` doesn't swallow; the UI shows failure instead of empty or stale state.
- **SQL** — migrations fail loudly and reversibly; transactions roll back rather than half-commit.
- **Rego** — fails closed; a missing `input` field never grants access.
- **Shell/PowerShell** — `set -euo pipefail` / `$ErrorActionPreference = 'Stop'`; exit codes and pipe failures checked.

## Patrol route (Go; same steps elsewhere)

1. **Every `err`.** Checked? Discarded? Overwritten before use? Zero/default returned after failure? Success reported despite partial failure?
2. **Propagation.** Cause kept with `%w` where callers need it; sentinels matched with `errors.Is/As`; storage or transport details not leaking upward by accident.
3. **Continuation.** Log-and-continue where it should stop; defaults masking broken config, DB, network, or validation; retries that exhaust silently; goroutines with no error path; `defer` cleanup whose failure matters.
4. **Boundaries.** Transactions, row scans and iteration errors, HTTP handlers and middleware, App → Business validation, Business → Storage conversion, context cancellation and timeouts.

## Gates

- **G4** — a swallowed error yields false success, corrupt data, skipped validation, or hidden failed persistence.
- **G3** — cause lost, hidden fallback, unobserved goroutine failure, silent retry exhaustion.
- **G2** — surfaced, but without useful context.
- **G1** — clearer wording or wrapping, same behavior.

## Extra fields

- Hidden failure: what disappears
- Impact: on caller, user, or operator
