---
name: pr-review
description: "Service DiffGuard: read-only PR review lenses for security (secrets/data-leak/vulnerability, mandatory), feature-completeness against acceptance criteria (unimplemented required behavior in unchanged files, mandatory when a ticket is supplied), correctness, error visibility, comment truthfulness, test coverage, type/contract boundaries, duplicate-code detection, and simplification across every language in the target service repo (Go, Vue/JS/SCSS, Rego, protobuf, SQL, Helm/YAML, shell). Drives a guided run: prompts for missing inputs (diff scope, issue-tracker URL, issue id), reviews the diff against the ticket's acceptance criteria, and writes auto-numbered findings and Mermaid diagram files under .reviews/<issue-id>/. USE whenever the user asks to review a PR or diff in any phrasing — \"review this PR\", \"review my PR\", \"PR review\", \"can you review this pull request\", \"review the diff/changes\", \"review my code before I commit\", \"pre-commit review\", \"look over these changes\", \"review the branch\", \"unstaged-diff review\", or a targeted review of any single aspect above (security, feature-completeness, correctness, error handling, tests, contracts, duplication, simplification)."
---

# Service DiffGuard

Reviews a diff through focused **lenses** (see the lens catalog). Each runs as a read-only Task subagent and returns **findings** on one shared scale. Lenses review code that is present; one lens — Spec Cartographer — instead hunts required behavior that is *absent*, including in files the diff never touched. Lenses advise only — never edit, stage, commit, disable tests, or bypass a failing check.

Default scope is the **unstaged `git diff`** unless the caller names files, a branch, a commit range, or a PR.

## Run inputs

This skill drives a full guided review. Gather these inputs; **ask only for what the invocation did not already supply**, then echo back what you parsed and wait for confirmation before launching lenses (per AGENTS.md: never assume, always confirm).

| Input                 | Purpose                                                                                      | If missing                                                                                                                                                                                                                                                                                                                                                                                                          |
|-----------------------|----------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Diff scope**        | What to review (files, branch, commit range, or PR).                                         | Ask; default to unstaged `git diff` only after confirming.                                                                                                                                                                                                                                                                                                                                                          |
| **Issue tracker URL** | Ticket / acceptance criteria to review the diff against.                                     | Ask for it, then fetch it and extract the acceptance criteria. **Fetch order:** prefer the tracker's own CLI or MCP when available (e.g. `gh issue view`, `jira`, GitLab/Linear/Jira MCP), fall back to `WebFetch` only if none is. Add a lens pass that checks the diff against the criteria.                                                                                                                      |
| **Issue id**          | Names the output directory `.reviews/<issue-id>/`, stable across every run of the same work. | Derive it **deterministically** — never invent an ad-hoc feature name (that is how one feature ends up with several review directories). Use the **issue id** when an issue-tracker URL/id was supplied; otherwise fall back to the **current git branch name** (`git rev-parse --abbrev-ref HEAD`). Slugify to a single path segment and confirm with the user before writing. Same work → same directory, always. |

On a **first run**, also gather the Security Sentinel prerequisites in this same up-front pass — see [Security Sentinel prerequisites](#security-sentinel-prerequisites-recallable-memory) below — folding them into the same gather-and-confirm step so no required input arrives mid-run.

Review posture is **skeptical, critical, adversarial**; be terse; do not prose. Confirm with the user before any decision; validate findings against the ticket.

## Security Sentinel prerequisites (recallable memory)

Before launching the mandatory Security Sentinel lens, resolve two persistent memories and pass their contents into the lens prompt:

| Memory                       | Holds                                                                        | If missing (first run)                                                                                                                                     |
|------------------------------|------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `security-tooling-inventory` | Which security tools are installed/available (scanners, SAST, deps).         | **Ask the user** what security tooling they have (gitleaks/trufflehog, semgrep/codeql, gosec/govulncheck, osv-scanner/trivy, LSP/MCP, …). Record verbatim. |
| `project-interaction-guide`  | How to run/drive the project (API endpoints, CLI, test harness, seed/login). | **Ask only when the lens needs to run the project.** Record the user's answer so later runs recall it.                                                     |

Recall these every run; ask again only for gaps or when the user says the environment changed. Write both as project-type memories with a one-line pointer in `MEMORY.md`.

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

## Verification discipline (mandatory)

Never trust a first-pass finding. Every finding is a hypothesis until it survives a deliberate attempt to disprove it. This applies at **both** levels and cannot be skipped:

- **Each lens**, before returning, re-reads its own findings adversarially and tries to **refute** each one: re-open the cited `file:line`, confirm the **Proof** actually shows what the finding claims, and ask "what would make this wrong?" — stale line numbers, code the diff didn't touch, behavior handled elsewhere, an intended design, a false pattern match. A finding that does not survive is dropped, downgraded, or moved to **Open checks** with the doubt stated. State the Gate only after this pass.
- **The aggregate**, before the report is final, runs the same skeptical re-read across the merged findings (the **Self-review pass** below).

When a finding depends on unverifiable intent, do not assert it — flag the assumption and confirm with the user. Second-guessing that costs a real finding is cheaper than a confident wrong one.

## Lens catalog

| Lens                   | Focus                                                                                                                                     | Reference prompt                  |
|------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------|
| **Security Sentinel**  | secrets, data leaks, vulnerabilities (mandatory)                                                                                          | `reference/security-sentinel.md`  |
| **Spec Cartographer**  | feature-completeness vs ACs; unimplemented required behavior in unchanged files; spec/AC weaknesses (mandatory when a ticket is supplied) | `reference/spec-cartographer.md`  |
| **Service Steward**    | general code correctness & conventions                                                                                                    | `reference/service-steward.md`    |
| **Error Tripwire**     | failure-path visibility                                                                                                                   | `reference/error-tripwire.md`     |
| **Doc Drift Check**    | comment truthfulness                                                                                                                      | `reference/doc-drift-check.md`    |
| **Harness Map**        | behavior-to-test mapping                                                                                                                  | `reference/harness-map.md`        |
| **Boundary Keeper**    | type & contract design across layers                                                                                                      | `reference/boundary-keeper.md`    |
| **Clone Hunter**       | duplicate code (intra/cross-domain, test↔target)                                                                                          | `reference/clone-hunter.md`       |
| **Straight-Line Pass** | behavior-preserving simplification                                                                                                        | `reference/straight-line-pass.md` |

## Languages in the target repo

Each lens reviews a changed file in its own language, applying its concept (security, correctness, failure visibility, comment truth, test coverage, contract design, duplicate detection, simplification) through that language's idioms. Go is primary, not the only one.

Paths below are **placeholders** — map each `<…>` to the target repo's actual directory (discover it from the diff, not from a fixed layout). An area the repo doesn't have is simply skipped.

| Area            | Where                                                                            | Lens focus                                                                                                             |
|-----------------|----------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------|
| Go services     | the repo's Go layer dirs (App/Business/Foundation/API by whatever names) (`.go`) | Full Go review; layered type rules and Go skills apply.                                                                |
| Frontend        | `<frontend-dir>` (`.vue`, `.js`, `.ts`, `.scss`)                                 | SFC/component structure, `props`/`emits` contracts, reactivity, async/`fetch` errors, a11y, leaked watchers/listeners. |
| Auth policies   | `<policy-dir>` (`.rego`)                                                         | Default-deny posture, `input` shape assumptions, unintended allows.                                                    |
| gRPC contracts  | `<grpc-contract-pkg>` (`.proto`)                                                 | Field-number stability, back/forward compatibility, breaking changes.                                                  |
| Database        | `<migrations-dir>` (`.sql`)                                                      | Migration reversibility/idempotency, indexing, locking, destructive changes, seed correctness.                         |
| Deploy / config | `<deploy-dir>` (`.yaml`, `.tpl`), `*.conf`                                       | Helm/k8s: resource limits, secrets, probes, value templating.                                                          |
| Scripts         | `*.sh`                                                                           | `set -euo pipefail`, quoting, exit-code handling.                                                                      |

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

- **Always, mandatory, no exceptions** (any diff, any language): Security Sentinel. Runs in Wave 1; cannot be skipped even for a "quick" or single-concern review.
- **Mandatory whenever an issue-tracker URL / acceptance criteria are supplied** (any diff, any language): Spec Cartographer. Runs in Wave 1. It is the only lens that hunts *absence* — required behavior missing from unchanged files — so it cannot be dropped from a ticketed review. With no ticket, run best-effort against the PR description/commits.
- **Always** (any production code, any language): Service Steward.
- **Production code or tests changed, or coverage asked:** Harness Map.
- **Any failure path touched** — Go `err`/`errors.Is/As`/wrapping/`defer`/`recover`/context, JS `try/catch`/promises/`await`/`fetch`, SQL transactions, Rego allow/deny, shell exit codes; plus logging and fallback/default behavior: Error Tripwire.
- **Any contract or shape changed** — Go structs/interfaces/constructors/converters/strong types/DB rows/stores, Vue `props`/`emits`, proto messages, SQL schema: Boundary Keeper.
- **Comments, doc strings, examples, README snippets, or TODO/FIXME changed:** Doc Drift Check.
- **Any non-trivial logic added or moved, or new tests added:** Clone Hunter — detect intra-domain, cross-domain, and test↔target duplication. Prefers native tooling (MCP/LSP/CLI clone detectors); harness inspection only as fallback.
- **Polish pass:** Straight-Line Pass — second wave after G4/G3 are resolved, or first wave only when simplification is explicitly requested.

## Execution

Run lenses as Task subagents. Read-only, so **parallel is safe** and preferred for a broad sweep; prefer **sequential** when scope is ambiguous, the diff is very large, or only one concern was requested.

### Choose the lens set (always ask)

Before launching, present the routed default and let the user pick the scope of the run via the native question UI (`AskUserQuestion`). Compute the routed set from **Lens routing** first, then offer at minimum:

- **Full run** — every lens in the catalog (all of Wave 1 + Wave 2), regardless of routing.
- **Wave 1 only (risk)** — list the Wave-1 lenses that routing selected, e.g. *Security Sentinel, Service Steward, Harness Map, Error Tripwire, Boundary Keeper, Doc Drift Check, and Spec Cartographer (when a ticket is supplied)*.
- **Wave 2 only (polish)** — list the Wave-2 lenses, e.g. *Clone Hunter, Straight-Line Pass* (plus the mandatory Security Sentinel, and Spec Cartographer when a ticket is supplied).
- **Routed default** — exactly the lenses routing selected for this diff (may span both waves).

Always name the concrete lenses inside each option so the choice is explicit. **Security Sentinel is mandatory in every option (including a Wave-2-only run) and Spec Cartographer is mandatory in every option whenever a ticket / acceptance criteria were supplied — neither can be dropped.** The user's selection overrides routing for this run.

Default two-wave plan (the ordering used once the set is chosen):

- **Wave 1 (risk):** Security Sentinel (mandatory), Spec Cartographer (mandatory when a ticket is supplied), Service Steward, Harness Map, plus Error Tripwire, Boundary Keeper, Doc Drift Check where applicable.
- **Wave 2 (polish):** Clone Hunter, Straight-Line Pass.

**Late stop-level findings reopen the risk gate.** Clone Hunter (Wave 2) can emit **G4/G3** (e.g. drifted authz or money-math logic duplicated in two places). Any G4/G3 from a Wave-2 lens reopens the risk gate: surface it at the top of the report and, if it invalidates a Wave-1 conclusion, re-run the affected Wave-1 lens.

When an issue-tracker URL is supplied, fetch the ticket (tracker CLI/MCP preferred, `WebFetch` fallback), list its criteria, and drive the **acceptance-criteria pass** through the **Spec Cartographer** lens — do not do it as a naive inline check. For each criterion: enumerate **every** site that must implement it from the codebase (not the diff), check each changed-or-not, and mark Met / Partial / Unmet / Not-addressed with `file:line` proof. A criterion proven at one site is **not** Met until its full site set is enumerated — a word like "all / every / everywhere / at access time" means more than one site is in scope. Treat an unmet or partially-met criterion as at least G3 (G4 for security/data-integrity). A site that appears to skip the behavior may not be dismissed as "by design" without proof or user confirmation. Also report **spec/AC weaknesses** (ambiguity, under-specification, illustrative-vs-normative, missing intent/edge criteria) with tightened wording. Validate — do not assume.

Launch each lens with a prompt of this shape:

```text
Use `.agents/skills/pr-review/reference/<lens>.md` as your review instructions.

Scope: <exact scope>
Diff source: <unstaged git diff | PR diff | branch range | file list>
Languages in scope: <e.g. Go; Vue/JS; Rego; proto; SQL; Helm/YAML; shell>
Repo context: polyglot monorepo (Go primary). Follow AGENTS.md; apply Go skills to .go files only.
Mode: advisory/read-only — do not modify files.

Before returning, second-guess every finding: try to refute it, re-open each cited file:line, and confirm the Proof holds. Drop, downgrade, or move to Open checks anything that does not survive.

Do NOT dismiss a suspicious gap or asymmetry as "by design", "intentional", or "handled elsewhere" on your own assumption — that rationalization is how real gaps ship. Either prove it out of scope from the ticket/code contract (cite it) or surface it as a finding with the assumption stated for the user to confirm.

Return a Gate report only, using the G0-G4 scale.
```

For **Security Sentinel**, build the prompt with two changes to the template above:

1. **Replace the `Mode:` line** with an explicit PoC carve-out so the lens is not told to do and not-do the same thing:

   ```text
   Mode: advisory/read-only — do not modify, stage, or commit existing files. You MAY create NEW proof-of-concept files, but ONLY under .reviews/<issue-id>/<NN>/security/<poc-name>/ (minimal, non-destructive, never hitting external hosts or real data).
   ```

2. Additionally pass the recalled `security-tooling-inventory` and (when it may run the project) `project-interaction-guide`, and note the lens may spawn adversarial read-only sub-agents whose only write permission is the same `.reviews/<issue-id>/<NN>/security/<poc-name>` path.

## Output artifacts

**Run isolation (mandatory).** Every run is independent. Do **not** read, diff against, or reference the contents of any previous run's artifacts (`findings.md`, `diagrams.md`, PoCs) unless the user explicitly instructs you to. You may *list* `.reviews/<issue-id>/` to pick the next `<NN>` — directory names only — but never open a prior run's files to inform, shortcut, compare, or "confirm fixes from" this review. Review only the diff in scope. Each run's artifacts must stand entirely on their own.

Every guided run writes to a single per-run directory `.reviews/<issue-id>/<NN>/` holding three artifact streams:

- **Findings:** `.reviews/<issue-id>/<NN>/findings.md` — one aggregate report per run.
- **Diagrams:** `.reviews/<issue-id>/<NN>/diagrams.md` — Mermaid diagrams for the feature.
- **Security PoCs:** `.reviews/<issue-id>/<NN>/security/<poc-name>/<test files>` — optional proof-of-concept tests the Security Sentinel writes to prove exploitability. Only stream allowed to create files beyond `.md` reports; minimal, non-destructive, never hits external hosts or real data.

**Numbering.** One `<NN>` per run, shared by all three streams. Scan `.reviews/<issue-id>/` for the highest existing `<NN>/` directory and use +1, zero-padded (`01`, `02`, …); if `.reviews/<issue-id>/` is absent, start at `01`. Create the `<NN>/` directory once, then write `findings.md`, `diagrams.md`, and any `security/<poc-name>/` under it. Never overwrite an existing run directory.

### Findings file

1. Write the aggregated report (format below) to the next `<NN>/findings.md`.
2. **Self-review pass:** re-read that file skeptically, critically, adversarially. Verify each finding against the diff and the ticket's acceptance criteria; drop or downgrade anything unproven. Update the file **in place**.
3. Make it **read standalone** — a reader seeing only this file understands the review. Do not reference the multi-pass process, earlier review files, or "the previous run".

### Diagrams file

Write `<NN>/diagrams.md` with several focused Mermaid diagrams covering, at minimum:

- the **data types** / entities the feature introduces or changes,
- how the **client interacts** with the feature (request/response or sequence), and
- the relevant **inner workings**.

**Skip the diagrams file** only when the diff in scope introduces or changes nothing the diagrams would show (no new/changed types, client contract, or flow) — judge this from the diff alone, never by comparing against a previous run's diagrams. State that it was skipped and why.

## Aggregation

Merge lens reports into one. Deduplicate overlapping findings by failure mode and location; on disagreement keep the higher Gate. This merged report is what gets written to `<NN>/findings.md` above.

**Report problems, not reassurance.** Focus the report on issues: the overall Gate, the Fix queue, and Open checks. Omit a "what's OK / what looks solid" section by default — add it back only when the user explicitly asks for it. (Diagrams are exempt: `diagrams.md` still depicts the whole feature.)

```markdown
# Service DiffGuard Report

Scope: <scope reviewed>
Overall Gate: G[0-4] — <Clear/Polish/Tighten/Repair/Stop>

## Run matrix
| Lens               | Result        | Notes |
|--------------------|---------------|-------|
| Security Sentinel  | Gx            | ...   |
| Spec Cartographer  | Gx / skipped  | ...   |
| Service Steward    | Gx            | ...   |
| Error Tripwire     | Gx / skipped  | ...   |
| Doc Drift Check    | Gx / skipped  | ...   |
| Harness Map        | Gx / skipped  | ...   |
| Boundary Keeper    | Gx / skipped  | ...   |
| Clone Hunter       | Gx / deferred | ...   |
| Straight-Line Pass | Gx / deferred | ...   |

## Acceptance-criteria coverage
<!-- From Spec Cartographer; include whenever a ticket was supplied. One row per criterion. -->
| Criterion | Verdict (Met/Partial/Unmet/Not-addressed) | Sites that must implement it | Proof / gap `file:line` |
|-----------|-------------------------------------------|------------------------------|-------------------------|

## Spec/AC weaknesses
<!-- Ambiguity, under-specification, illustrative-vs-normative, missing intent/edge criteria — each with tightened wording. Omit only if none. -->

## Fix queue
### G4 Stop
- [lens] <title> — `file.go:line`
    - Proof:
    - Patch direction:
    - Verify:
### G3 Repair
### G2 Tighten
### G1 Polish

## Open checks
- <Anything not reviewed, unavailable, or needing human confirmation.>

## Suggested verification
- Go: `make test` (unit) / `make test-integration` (integration), or `go test ./path/...` for one package.
- Frontend: the project's JS test/lint/build scripts in `<frontend-dir>`.
- SQL/Rego/proto: the relevant migration, policy, or codegen check.
- Re-run affected lenses after fixes.
```
