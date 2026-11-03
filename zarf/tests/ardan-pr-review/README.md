# ardan-pr-review test suite

Regression tests for the skill's scripts (`.agents/skills/ardan-pr-review/scripts/`). Run them after any change to a script or to the file classification, symbols, signals, or checks.

```
make test-pr-review            # host + container
make test-pr-review-host       # stub analyzers, the host's sh/awk/sed and PowerShell (needs git, pwsh, rg, jq)
make test-pr-review-container  # real analyzers at pinned versions (needs Docker)
make test-pr-review-update     # rewrite expected/ after an intended change; review the diff
```

CI (`.github/workflows/ardan-pr-review.yml`) runs `lint`, host mode on Linux and macOS, and container mode on every PR that touches the skill or these tests.

## What it checks

`fixture.sh` builds a git repo whose feature branch has real, tool-detectable problems in every ecosystem the scripts know (Go, Rust, Python, Terraform, Helm, Kustomize, plain K8s, Ansible, Dockerfile, GitHub Actions, Java as an unmapped language), plus a generated file and a symlink. `suite.sh` then asserts:

- **sh ↔ PowerShell parity** — `intake.sh`/`intake.ps1` write identical context files at diff, project, and packages + `--include-generated` depth; `checks.sh`/`checks.ps1` give the same check, status, and lens; both `extract-findings` ports save the same files.
- **Golden results** — `expected/` holds the intake outputs (files, stack, symbols, refs, signals, review sets, …) and the check statuses per mode (`host.checks.tsv`, `container.checks.tsv`, `tofu.*`).
- **Trust** — a fake `gh` (`stub-gh.sh`) drives `--pr` runs: only an author with write access on a base-repo branch gets `trust=maintainer`; read access or a fork stays untrusted. Code-executing checks are skipped in the untrusted runs (`*.checks.tsv`) and run in the maintainer run (`*.trusted.checks.tsv`).
- **Read-only** — checks leave `git status` unchanged (cargo's gitignored `target/` excepted), including Terraform init and the OpenTofu pass.

Host mode replaces every analyzer with a stub, so it tests routing and both ports on BSD (macOS) and GNU (Linux) userlands. Container mode runs the real tools from `Dockerfile`.

## Changing things

- **Script change with intended output changes:** `make test-pr-review-update`, then read the `expected/` diff before committing.
- **Tool upgrade:** bump the `ARG` in `Dockerfile`, run `make test-pr-review-container`; a changed status means the tool changed behavior — confirm it, then update.
- Network access is needed in container mode: Terraform providers, advisory databases (cargo-audit, pip-audit, govulncheck), trivy's check bundle, kubeconform schemas.
