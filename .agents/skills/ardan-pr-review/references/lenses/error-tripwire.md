# Error Tripwire (failure-path visibility)

Follow every in-scope failure path (every changed one, at `diff` depth) to its end and ask: when this fails, who finds out, and is that enough to debug it? Catch defaults returned after errors, log-and-continue, success reported after partial failure, and configuration that fails open. Use the **Failure paths** section of each idiom file in your prompt; `lens=error-tripwire` rows in `checks/` flag unchecked errors mechanically — start there, then go further.

## Patrol route

1. **Every failure.** Checked? Discarded? Overwritten before use? A default returned after failure? Success reported despite partial failure?
2. **Propagation.** Cause kept where callers need it; typed errors matched, not string-compared; storage or transport details not leaking upward by accident.
3. **Continuation.** Log-and-continue where it should stop; defaults masking broken config, DB, network, or validation; retries that exhaust silently; background work with no error path; cleanup whose failure matters; `ignore_errors`, `continue-on-error`, `|| true`, `try()`/`can()` hiding real failures.
4. **Boundaries.** Transactions, iteration and scan errors, request handlers and middleware, layer crossings, cancellation and timeouts, deploy-time validation (preconditions, `required`, probes, health checks).

## Gates

- **G4** — a swallowed error yields false success, corrupt data, skipped validation, hidden failed persistence, or a deploy that reports success while broken.
- **G3** — cause lost, hidden fallback, unobserved background failure, silent retry exhaustion.
- **G2** — surfaced, but without useful context.
- **G1** — clearer wording or wrapping, same behavior.

## Extra fields

- Hidden failure: what disappears
- Impact: on caller, user, or operator
