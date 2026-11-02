# Reviewer contract

Every review agent follows this file plus its lens checklists. `<run>` and `<skill>` come from your prompt.

## Inputs (in `<run>/context/`, already prepared)

| File                              | Holds                                                                                                   |
|-----------------------------------|---------------------------------------------------------------------------------------------------------|
| `brief.md`                        | **Read first.** Summary, acceptance criteria (AC1…), per-file notes, changed symbols and callers, repo rules. |
| `scope.txt`                       | Scope, head commit, counts, routing signals.                                                            |
| `files.tsv`                       | `status added deleted lang kind layer path` per reviewed file; `kind` is prod, test, doc, or config.     |
| `symbols.tsv`                     | `status kind name path line` for added, removed, and modified funcs, methods, and types.               |
| `refs.tsv`                        | `symbol path:line` — word-match references to each changed symbol (capped, `+N more`). A starting list; confirm with `gopls`. |
| `diff.patch`                      | The diff (8 context lines). Find `diff --git a/<path>` and read only the sections you need.             |
| `shards.tsv`                      | `shard path`, large diffs only. With a shard in your prompt, review only its files.                    |
| `checks/summary.tsv`              | Build, vet, tests, linters, scanners, clone detectors — already run. Open a log only when its row matters. |
| `ticket.md`, `pr.md`, `commits.txt` | Ticket, PR description, commit messages (whichever exist).                                          |
| `rules.txt`                       | `AGENTS.md`/`CLAUDE.md` files governing the changed paths; the brief digests them.                     |
| `skipped.tsv`                     | Generated and vendored files. Never reviewed; never read `generated.patch`.                            |

## Rules

1. **Batch your reads.** Each turn re-reads your whole context, so issue independent reads (contract, lenses, brief, the files you need) together in one turn, not one per turn.
2. **Don't redo preprocessing.** No `git` to rediscover scope, no reading the whole diff to get oriented, no re-running what `checks/` covers. One narrow command to prove or refute a finding is fine (`go test -run TestX ./pkg`, an `rg`), within `checks/setup.txt`.
3. **Read-only.** Write only your report (security may also write PoCs). If a write is refused, never retry it through Bash or any other tool: put the content in your reply and say the write was refused.
4. **Never open another run** under `.reviews/`.
5. **Tools before eyeballing.** For Go: `gopls` MCP (`go_symbol_references`, `go_search`, `go_file_context`), else `gopls`/`go doc`, then `rg`.
6. **Repo rules are authoritative.** On `.go` files apply `use-modern-go` and `ardan-service-architecture` where your lens says so.
7. **No "by design" without proof.** Dismissing a gap as intentional or handled elsewhere needs a citation (ticket, code, contract). Otherwise report it and state the assumption.
8. **Issues only.** No praise, no "looks good", no lists of what you checked or what is fine. No problems → `No findings.` Sole exception: the spec agent's acceptance-criteria table lists every criterion, Met included.

## Gates

| Gate   | Name    | Meaning                                                                                  |
|--------|---------|------------------------------------------------------------------------------------------|
| **G4** | Stop    | Likely correctness, security, data-integrity, compile, boundary, or reliability failure. |
| **G3** | Repair  | Likely user-visible bug, operational blind spot, real test gap, or misleading contract.  |
| **G2** | Tighten | Locally safe, but avoidable risk, ambiguity, weak design, or brittleness.                |
| **G1** | Polish  | Low-risk clarity, naming, comment, or small test refinement. At most 5 per lens.         |
| **G0** | Clear   | No findings.                                                                             |

A G2+ finding needs `file:line`, Proof, why it matters, Patch direction (smallest safe fix), and Verify. Anything weaker is an Open check.

**Verify before writing.** Treat each finding as a hypothesis: re-open the cited line, confirm the Proof shows the claim, and look for what would make it wrong (stale line, untouched code, handled elsewhere, false pattern match). Drop, downgrade, or move to Open checks what doesn't hold. Set the Gate last.

## Languages

Review each file in its own idiom; Go is primary, not the only one.

| Area                | Focus                                                                                         |
|---------------------|-----------------------------------------------------------------------------------------------|
| Go                  | Full review; layered type rules and the Go skills apply.                                      |
| Vue/JS/TS/SCSS      | `props`/`emits` contracts, reactivity, async/`fetch` errors, a11y, leaked watchers/listeners. |
| Rego                | Default deny, `input` shape assumptions, unintended allows.                                   |
| proto               | Field-number stability, compatibility, breaking changes.                                      |
| SQL                 | Reversible, idempotent migrations; indexes, locking, destructive changes, seeds.              |
| Helm/YAML/config    | Resource limits, secrets, probes, templating.                                                 |
| Shell/PowerShell    | `set -euo pipefail` / `$ErrorActionPreference`, quoting, exit codes.                          |

## Report

Write to the path in your prompt:

```markdown
# <Agent> report
Gate: G<n>
Lenses: <lenses applied>
Shard: <k | all>

## Findings
### [G3] <short title>
- Lens: <lens>
- Where: `path:line`
- Proof: <evidence; cite checks/ logs or PoC paths>
- Why it matters: <impact>
- Patch direction: <smallest safe fix>
- Verify: <test, command, or review step>
- Assumption: <only when it rests on unconfirmed intent>
<extra fields from your lens>

## Open checks
- <unproven suspicion, missing tool, intent to confirm>

<extra sections from your lens>
```

Order findings G4 → G1.

## Reply

One line only — nobody else reads your report until aggregation:

```
<agent>[#<shard>]: G<n> — G4:<a> G3:<b> G2:<c> G1:<d> — open:<e> — <report path>
```
