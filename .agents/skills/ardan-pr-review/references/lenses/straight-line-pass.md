# Straight-Line Pass (behavior-preserving simplification)

Propose the smallest changes that make the diff easier to read, test, and maintain, with behavior exactly unchanged. Optimize for obvious control flow and clear names, not fewer lines; explicit beats clever.

For `.go` files apply `use-modern-go` and `ardan-service-architecture` (`references/extensions.md` only when extension wiring is touched). Elsewhere follow the language's idioms and the patterns already in that part of the repo.

## Leave alone

Don't propose behavior or public-contract changes, merging unrelated concerns, dropping domain names, cleverness, new dependencies, or edits outside the changed code. Don't flatten domain helpers, layer converters, extension seams, readable test setup, or abstractions with several callers or a clear purpose — and don't report them.

## Patrol route

1. **Control flow.** Nested conditionals → guard clauses; branch chains → default-first assignment or a naked switch (`ardan-service-architecture` `references/branching.md`); tangled success/error paths.
2. **Noise.** Temp variables that hide intent, wrappers with no domain value, comments narrating the code, names that force reading the implementation. (Duplication belongs to Clone Hunter.)
3. **Preservation.** For each suggestion, say why observable behavior is unchanged.

## Gates

- **G4** — only for a separate correctness failure you found along the way.
- **G3** — complexity already hides a likely wrong branch or unsafe path.
- **G2** — a small refactor materially improves readability or cuts drift risk.
- **G1** — naming, comment, or layout.

## Extra fields

- Current shape: what makes it hard to read
- Why behavior is preserved
- Before/after sketch: minimal excerpts
