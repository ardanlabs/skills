---
name: review-pr
description: "Service DiffGuard: read-only PR review lenses for correctness, error visibility, comment truthfulness, test coverage, type/contract boundaries, and simplification across every language in the target service repo (Go, Vue/JS/SCSS, Rego, protobuf, SQL, Helm/YAML, shell). Drives a guided run: prompts for missing inputs (diff scope, issue-tracker URL, issue id), reviews the diff against the ticket's acceptance criteria, and writes auto-numbered findings and Mermaid diagram files under .reviews/<issue-id>/. Use for PR review, pre-commit review, unstaged-diff review, or a targeted review of one of those aspects."
---

# Service DiffGuard

Reviews a diff through six focused **lenses**. Each runs as a read-only Task subagent and returns **findings** on one shared scale. Lenses advise only — never edit, stage, commit, disable tests, or bypass a failing check.

Default scope is the **unstaged `git diff`** unless the caller names files, a branch, a commit range, or a PR.

## Run inputs

This skill drives a full guided review. Gather these inputs; **ask only for what the invocation did not already supply**, then echo back what you parsed and wait for confirmation before launching lenses (per AGENTS.md: never assume, always confirm).

| Input | Purpose | If missing |
|-------|---------|------------|
| **Diff scope** | What to review (files, branch, commit range, or PR). | Ask; default to unstaged `git diff` only after confirming. |
| **Issue tracker URL** | Ticket / acceptance criteria to review the diff against. | Ask for it, then fetch it and extract the acceptance criteria. **Fetch order:** prefer the tracker's own CLI or MCP when available (e.g. `gh issue view`, `jira`, GitLab/Linear/Jira MCP), fall back to `WebFetch` only if none is. Add a lens pass that checks the diff against the criteria. |
| **Issue id** | Names the output directory `.reviews/<issue-id>/`. | Ask, or derive from the ticket URL and confirm. |

Review posture is **skeptical, critical, adversarial**; be terse; do not prose. Confirm with the user before any decision; validate findings against the ticket.

## Gate scale

Every finding carries a Gate; the run's overall Gate is the highest any lens returns.

| Gate   | Name    | Meaning                                                                                  | Action                                               |
|--------|---------|------------------------------------------------------------------------------------------|------------------------------------------------------|
| **G4** | Stop    | Likely correctness, security, data-integrity, compile, boundary, or reliability failure. | Block merge until fixed.                             |
| **G3** | Repair  | Likely user-visible bug, operational blind spot, real test gap, or misleading contract.  | Fix before the PR is ready.                          |
| **G2** | Tighten | Locally safe but leaves avoidable risk, ambiguity, weak design, or brittleness.          | Address if reasonably scoped; otherwise acknowledge. |
| **G1** | Polish  | Low-risk clarity, naming, comment, or small test refinement.                             | Optional; batch, don't spam.                         |
| **G0** | Clear   | No issue, or a positive observation.                                                     | None.                                                |

Every **G2+** finding must include: `file:line`, **Proof** (diff evidence), why it matters, **Patch direction** (smallest safe fix), and how to verify. Weak/speculative observations go under **Open checks**, not as findings. Cap **G1** at five per lens unless exhaustive polish is requested.

## Lens catalog

| Lens                   | Focus                                  | Reference prompt                  |
|------------------------|----------------------------------------|-----------------------------------|
| **Service Steward**    | general code correctness & conventions | `reference/service-steward.md`    |
| **Error Tripwire**     | failure-path visibility                | `reference/error-tripwire.md`     |
| **Doc Drift Check**    | comment truthfulness                   | `reference/doc-drift-check.md`    |
| **Harness Map**        | behavior-to-test mapping               | `reference/harness-map.md`        |
| **Boundary Keeper**    | type & contract design across layers   | `reference/boundary-keeper.md`    |
| **Straight-Line Pass** | behavior-preserving simplification     | `reference/straight-line-pass.md` |

## Languages in the target repo

Each lens reviews a changed file in its own language, applying its concept (correctness, failure visibility, comment truth, test coverage, contract design, simplification) through that language's idioms. Go is primary, not the only one.

| Area            | Where                                                     | Lens focus |
|-----------------|-----------------------------------------------------------|------------|
| Go services     | `app/**`, `business/**`, `foundation/**`, `api/**` (`.go`) | Full Go review; layered type rules and Go skills apply. |
| Admin frontend  | `api/frontends/admin/src` (`.vue`, `.js`, `.scss`)        | Vue SFC structure, `props`/`emits` contracts, reactivity, async/`fetch` errors, a11y, leaked watchers/listeners. |
| Auth policies   | `app/sdk/auth/rego` (`.rego`)                             | Default-deny posture, `input` shape assumptions, unintended allows. |
| gRPC contracts  | `app/domain/grpcauthapp` (`.proto`)                       | Field-number stability, back/forward compatibility, breaking changes. |
| Database        | `business/sdk/migrate/sql` (`.sql`)                       | Migration reversibility/idempotency, indexing, locking, destructive changes, seed correctness. |
| Deploy / config | `zarf/**` (`.yaml`, `.tpl`), `*.conf`                     | Helm/k8s: resource limits, secrets, probes, value templating. |
| Scripts         | `*.sh`                                                    | `set -euo pipefail`, quoting, exit-code handling. |

## Repo-local authority

All lenses treat **AGENTS.md** (and any nested AGENTS.md) as authoritative. Apply these repo skills **only to `.go` files**, where relevant:

- `use-modern-go` — Go implementation style.
- `layered-architecture-types` — primitives at edges, strong types in Business, named converters only.
- `business-layer-extensions` — the `ExtBusiness` / `Extension` decorator seam.
- `branching-logic-flow` — defaulting and shallow control flow.

## Diff intake

1. Resolve scope from the caller.
2. With no explicit scope, inspect unstaged changes: `git status --short`, `git diff --name-only`, `git diff`. For a branch/PR: `git diff --name-only <base>...HEAD` or `gh pr diff`.
3. Build a short change inventory: which languages/areas changed; production vs test; App/Business/Storage files; comments/docs; error handling; new or modified types, interfaces, converters, component contracts, proto messages, SQL schema; PR title if in scope.

## Lens routing

Route by what changed unless the caller asks for "full", "all", or "PR-ready".

- **Always** (any production code, any language): Service Steward.
- **Production code or tests changed, or coverage asked:** Harness Map.
- **Any failure path touched** — Go `err`/`errors.Is/As`/wrapping/`defer`/`recover`/context, JS `try/catch`/promises/`await`/`fetch`, SQL transactions, Rego allow/deny, shell exit codes; plus logging and fallback/default behavior: Error Tripwire.
- **Any contract or shape changed** — Go structs/interfaces/constructors/converters/strong types/DB rows/stores, Vue `props`/`emits`, proto messages, SQL schema: Boundary Keeper.
- **Comments, doc strings, examples, README snippets, or TODO/FIXME changed:** Doc Drift Check.
- **Polish pass:** Straight-Line Pass — second wave after G4/G3 are resolved, or first wave only when simplification is explicitly requested.

## Execution

Run lenses as Task subagents. Read-only, so **parallel is safe** and preferred for a broad sweep; prefer **sequential** when scope is ambiguous, the diff is very large, or only one concern was requested.

Default two-wave plan:

- **Wave 1 (risk):** Service Steward, Harness Map, plus Error Tripwire, Boundary Keeper, Doc Drift Check where applicable.
- **Wave 2 (polish, optional):** Straight-Line Pass.

When an issue-tracker URL is supplied, add an **acceptance-criteria pass**: fetch the ticket (tracker CLI/MCP preferred, `WebFetch` fallback), list its criteria, and mark each Met / Partial / Unmet / Not-addressed against the diff, with `file:line` proof. Treat an unmet criterion as at least G3. Validate — do not assume — and confirm ambiguous criteria with the user.

Launch each lens with a prompt of this shape:

```text
Use `.agents/skills/review-pr/reference/<lens>.md` as your review instructions.

Scope: <exact scope>
Diff source: <unstaged git diff | PR diff | branch range | file list>
Languages in scope: <e.g. Go; Vue/JS; Rego; proto; SQL; Helm/YAML; shell>
Repo context: polyglot monorepo (Go primary). Follow AGENTS.md; apply Go skills to .go files only.
Mode: advisory/read-only — do not modify files.

Return a Gate report only, using the G0-G4 scale.
```

## Output artifacts

Every guided run writes to `.reviews/<issue-id>/`. Two independently auto-numbered streams:

- **Findings:** `.reviews/<issue-id>/findings/<NN>.md` — one aggregate report per run.
- **Diagrams:** `.reviews/<issue-id>/diagrams/<NN>.md` — Mermaid diagrams for the feature.

**Numbering.** For each stream, scan its directory for the highest existing `NN` and use +1, zero-padded (`01`, `02`, …). The two streams increment independently — do not force them to share a number. Never overwrite an existing file. If a directory is absent, start at `01`.

### Findings file

1. Write the aggregated report (format below) to the next `findings/<NN>.md`.
2. **Self-review pass:** re-read that file skeptically, critically, adversarially. Verify each finding against the diff and the ticket's acceptance criteria; drop or downgrade anything unproven. Update the file **in place**.
3. Make it **read standalone** — a reader seeing only this file understands the review. Do not reference the multi-pass process, earlier review files, or "the previous run".

### Diagrams file

Write `diagrams/<NN>.md` with several focused Mermaid diagrams covering, at minimum:

- the **data types** / entities the feature introduces or changes,
- how the **client interacts** with the feature (request/response or sequence), and
- the relevant **inner workings**.

**Skip the diagrams file** when the diff since the previous review run does not change what the diagrams would show (types, client contract, flow). State that it was skipped and why.

## Aggregation

Merge lens reports into one. Deduplicate overlapping findings by failure mode and location; on disagreement keep the higher Gate. This merged report is what gets written to `findings/<NN>.md` above.

```markdown
# Service DiffGuard Report

Scope: <scope reviewed>
Overall Gate: G[0-4] — <Clear/Polish/Tighten/Repair/Stop>

## Run matrix
| Lens               | Result        | Notes |
|--------------------|---------------|-------|
| Service Steward    | Gx            | ...   |
| Error Tripwire     | Gx / skipped  | ...   |
| Doc Drift Check    | Gx / skipped  | ...   |
| Harness Map        | Gx / skipped  | ...   |
| Boundary Keeper    | Gx / skipped  | ...   |
| Straight-Line Pass | Gx / deferred | ...   |

## Fix queue
### G4 Stop
- [lens] <title> — `file.go:line`
  - Proof:
  - Patch direction:
  - Verify:
### G3 Repair
### G2 Tighten
### G1 Polish

## Clear signals
- <What looks solid and why.>

## Open checks
- <Anything not reviewed, unavailable, or needing human confirmation.>

## Suggested verification
- Go: `make test` (unit) / `make test-integration` (integration), or `go test ./path/...` for one package.
- Frontend: the project's JS test/lint/build scripts in `api/frontends/admin`.
- SQL/Rego/proto: the relevant migration, policy, or codegen check.
- Re-run affected lenses after fixes.
```
