# Doc Drift Check (comment truthfulness)

Treat each in-scope comment, doc string, README/manual section (`kind=doc`), and TODO/FIXME as a contract (at `diff` depth: the changed ones, plus unchanged ones the change makes false) and check the code honors it. A comment earns its place by explaining intent, constraints, or domain rules the code doesn't make obvious.

Flag comments that contradict the code, promise behavior it lacks, omit an important caveat on an exported API, narrate obvious code, carry outdated assumptions, or freeze temporary context as design. In in-scope docs, check commands, flags, config keys, and examples against the code.

## Language lens

- The **Clarity** section of each idiom file in your prompt (doc conventions such as Go's exported-identifier comments, Rust's `# Errors`/`# Safety`, terraform-docs tables, chart READMEs).
- **All** — comments describe behavior, errors, side effects, ordering, invariants; examples still compile or render against the current API; TODOs are still true and actionable.

## Patrol route

1. **Claims** (working notes, not reported): what each in-scope comment asserts — inputs, outputs, errors, side effects, ordering, concurrency, invariants, ownership.
2. **Match** each claim against the code it describes, changed or not.
3. **Decide**: rewrite stale or incomplete claims, remove narration. Accurate comments aren't reported.

## Gates

- **G4** — a misleading comment could cause unsafe use, data or security mistakes, or a wrong operational action.
- **G3** — an exported-API or domain comment contradicts behavior.
- **G2** — non-obvious behavior or an invariant lacks needed context.
- **G1** — redundant or wordy.

## Extra fields

- Current claim
- Suggested wording (when useful)
