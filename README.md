# skills

A collection of AI skills for development work, primarily Go. Compatible with Claude Code and other agents that read the `.agents/skills` convention.

## Agent instructions

| File                     | Purpose                                                                                                    |
|--------------------------|------------------------------------------------------------------------------------------------------------|
| [AGENTS.md](AGENTS.md)   | The agent's identity, working style, git policy, and mandatory-skill triggers.                             |
| [CLAUDE.md](CLAUDE.md)   | Claude Code entry point — points at `AGENTS.md`.                                                           |

## Skills

| Skill                                                                            | Purpose                                                                                                                                                        |
|----------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [use-modern-go](.agents/skills/use-modern-go/SKILL.md)                           | Apply modern Go syntax based on the project's Go version.                                                                                                      |
| [ardan-service-architecture](.agents/skills/ardan-service-architecture/SKILL.md) | Service layering (primitives at edges, strong types in Business, named converters), the `ExtBusiness`/`Extension` decorator seam, and default-first branching. |
| [ardan-pr-review](.agents/skills/ardan-pr-review/SKILL.md)                       | Guided read-only PR review for code and infrastructure in any language: scripted intake and per-ecosystem checks, stack discovery, parallel lens agents, issues-only findings and color-coded Mermaid diagrams. |

## Install as a Claude Code plugin

This repo is a [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) named `ardanlabs`. Each skill is a separate plugin, so you install only the ones you want.

```
/plugin marketplace add ardanlabs/skills
/plugin install ardan-pr-review@ardanlabs
/reload-plugins
```

Available plugins: `use-modern-go`, `ardan-service-architecture`, `ardan-pr-review`.

Plugin skills are namespaced, so `ardan-pr-review` is invoked as `/ardan-pr-review:ardan-pr-review`. Pull newer versions with `/plugin marketplace update ardanlabs` — plugins are unpinned, so every commit to `main` is a new version.

## PR review tools

`ardan-pr-review` runs the tools below when the change needs them, per ecosystem (Go module, crate, Terraform module, chart, …). A missing tool is listed with its install command at the start of a review, and its check is skipped. Go tools built with an older Go than the active toolchain are flagged for a rebuild: analyzers fail on a newer standard library. Ecosystems not listed here are found by a discovery agent, which also offers the repo's own quality gates (Makefile, CI, pre-commit) as extra checks; only the ones you approve run.

| Tool                                 | Checks                                          | Install                                                                      |
|--------------------------------------|-------------------------------------------------|------------------------------------------------------------------------------|
| `go` (`build`, `vet`, `test -race`, `fix -diff`, `mod tidy -diff`, `gofmt`) | build, vet, tests and data races, modernizers, module and format hygiene | [go.dev/dl](https://go.dev/dl/); `-race` needs cgo and a C compiler |
| `staticcheck`                        | Go correctness and simplifications              | `go install honnef.co/go/tools/cmd/staticcheck@latest`                       |
| `golangci-lint`                      | the repo's own lint config, when it has one     | `go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest`   |
| `checklocks`                         | `+checklocks` lock and atomic annotations       | `go install gvisor.dev/gvisor/tools/checklocks/cmd/checklocks@go`            |
| `errcheck`                           | unchecked errors                                | `go install github.com/kisielk/errcheck@latest`                              |
| `nilaway`                            | nil dereferences                                | `go install go.uber.org/nilaway/cmd/nilaway@latest`                          |
| `deadcode`                           | unreachable functions                           | `go install golang.org/x/tools/cmd/deadcode@latest`                          |
| `apidiff`                            | exported Go API breaks against the base commit  | `go install golang.org/x/exp/cmd/apidiff@latest`                             |
| `gosec`                              | Go security                                     | `go install github.com/securego/gosec/v2/cmd/gosec@latest`                   |
| `govulncheck`                        | known vulnerabilities                           | `go install golang.org/x/vuln/cmd/govulncheck@latest`                        |
| `dupl`                               | Go clones                                       | `go install github.com/mibk/dupl@latest`                                     |
| `gopls`                              | symbol lookups by reviewers                     | `go install golang.org/x/tools/gopls@latest`                                 |
| `buf`                                | proto lint and breaking changes (`buf.yaml`)    | `go install github.com/bufbuild/buf/cmd/buf@latest`                          |
| `gitleaks`                           | secrets in the diff                             | `go install github.com/zricethezav/gitleaks/v8@latest`                       |
| `shellcheck`                         | shell scripts                                   | [shellcheck#installing](https://github.com/koalaman/shellcheck#installing)   |
| `jscpd`                              | JS/TS clones                                    | `npm install -g jscpd`                                                       |
| `semgrep`                            | the repo's own semgrep rules, when it has them  | `python3 -m pip install semgrep`                                             |
| `cargo` (`fmt --check`, `clippy`, `test`) | Rust format, lints, tests (`--locked`)     | [rustup.rs](https://rustup.rs); `rustup component add clippy rustfmt`        |
| `cargo-audit`, `cargo-deny`          | Rust advisories; licenses and sources (`deny.toml`) | `cargo install cargo-audit cargo-deny --locked`                          |
| `terraform` or `tofu` (`fmt`, `init -backend=false`, `validate`) | Terraform/OpenTofu format and validation; init uses a temp data dir and never rewrites the lock file | [terraform](https://developer.hashicorp.com/terraform/install), [opentofu](https://opentofu.org/docs/intro/install/) |
| `tflint`                             | Terraform lint (repo `.tflint.hcl`)             | [tflint#installation](https://github.com/terraform-linters/tflint#installation) |
| `helm` (`lint`, `template`)          | chart lint and render                           | [helm.sh](https://helm.sh/docs/intro/install/)                               |
| `kustomize` or `kubectl kustomize`   | render Kustomize roots                          | `go install sigs.k8s.io/kustomize/kustomize/v5@latest`                       |
| `kubeconform`                        | K8s schema validation of manifests and renders  | `go install github.com/yannh/kubeconform/cmd/kubeconform@latest`             |
| `kube-linter`                        | K8s best practices                              | `go install golang.stackrox.io/kube-linter/cmd/kube-linter@latest`           |
| `trivy` (else `checkov`)             | IaC misconfiguration: Terraform, charts, manifests, Dockerfiles | [trivy.dev](https://trivy.dev/latest/getting-started/installation/) |
| `ruff`, `mypy`, `pytest`             | Python lint/format, types (repo config), tests  | `python3 -m pip install ruff mypy pytest`                                    |
| `bandit`, `pip-audit`                | Python security; advisories (`requirements*.txt`) | `python3 -m pip install bandit pip-audit`                                  |
| `ansible-lint`, `yamllint`           | Ansible lint; YAML lint (repo config)           | `python3 -m pip install ansible-lint yamllint`                               |
| `hadolint`                           | Dockerfiles                                     | [hadolint#install](https://github.com/hadolint/hadolint#install)             |
| `actionlint`, `zizmor`               | GitHub Actions lint and security                | `go install github.com/rhysd/actionlint/cmd/actionlint@latest`; `python3 -m pip install zizmor` |

`checklocks` is installed from gVisor's `go` branch, the only one that builds with plain `go install`.

Changes to the skill's scripts are verified by `make test-pr-review` (see [zarf/tests/ardan-pr-review](zarf/tests/ardan-pr-review/README.md)): a fixture repo covering every supported ecosystem, golden results, and sh ↔ PowerShell parity, with stub analyzers on the host and the real tools above in a pinned Docker image.

## Claude Code settings

Example Claude Code configuration, split into global (user-level) and project-level.

| File                                                                                                | Purpose                                                                                             |
|-----------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| [global/.claude/settings.json](claude/global/.claude/settings.json)                                 | User settings: permission allow/deny lists, model, plugins, Go-version SessionStart hook.           |
| [global/claude.json](claude/global/claude.json)                                                     | MCP servers (`gopls`, `goland`).                                                                    |
| [global/statusline.sh](claude/global/statusline.sh)                                                 | Powerline statusline: model, dir, git state, context/cost/edits.                                    |
| [project/.claude/settings.json](claude/project/.claude/settings.json)                               | Shared project settings: git/gh permissions, git-policy PreToolUse hook, SessionStart instructions. |
| [project/.claude/settings.local.json](claude/project/.claude/settings.local.json)                   | Local per-machine permission grants (example).                                                      |
| [project/.claude/hooks/git-policy-reminder.py](claude/project/.claude/hooks/git-policy-reminder.py) | PreToolUse hook reminding the agent of git/GitHub policy before write ops.                          |

## Layout

```
AGENTS.md           # agent identity, policy, and skill triggers
CLAUDE.md           # Claude Code entry point -> AGENTS.md
.agents/skills/     # canonical skill files
.claude/skills      # symlink -> ../.agents/skills
.claude-plugin/     # marketplace.json — plugin catalog pointing at .agents/skills
claude/global/      # example user-level Claude Code config
claude/project/     # example project-level Claude Code config
Makefile            # `make test`: lint + skill test suites
zarf/tests/         # skill test suites (ardan-pr-review: fixture, golden results, tools image)
.github/workflows/  # CI running those suites
```

`.claude/skills` is a symlink so Claude Code and `.agents`-aware tools share one source.

## Windows setup

> [!IMPORTANT]
> The `.claude/skills` symlink requires git symlink support on Windows. Without it, git checks out the link as a plain text file and skills fail to load.
>
> Enable it **before cloning**:
> ```
> git config --global core.symlinks true
> ```
> Creating the symlink also needs OS permission to do so — **either** run git in
> an elevated (admin) shell, **or** enable Windows Developer Mode
> (Settings → Privacy & security → For developers).
>
> If a clone already checked out `.claude/skills` as a text file:
> ```
> git config core.symlinks true
> git checkout -- .claude/skills
> ```
