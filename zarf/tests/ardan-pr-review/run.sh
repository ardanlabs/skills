#!/bin/sh
# Usage: sh run.sh host|container
# Entry point for the ardan-pr-review regression suite (suite.sh). Called by `make test-pr-review*`.
#   host       stub analyzers on PATH; needs git, pwsh, rg, jq on the host.
#   container  builds the pinned tools image (Dockerfile) and runs the suite inside it; needs Docker.
# Environment: UPDATE=1 rewrites expected/ from the run; IMAGE=name picks the image tag
# (default ardan-pr-review-tools); NO_BUILD=1 uses an existing image (CI builds it with caching);
# KEEP=1 keeps the host work directory.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
skill=$(cd "$here/../../../.agents/skills/ardan-pr-review" && pwd)

die() { echo "run: $*" >&2; exit 2; }

case ${1-} in
  host)
    for t in git pwsh rg jq; do command -v "$t" >/dev/null 2>&1 || die "$t is required on the host"; done
    work=$(mktemp -d)
    [ "${KEEP-}" = 1 ] || trap 'rm -rf "$work"' EXIT
    mkdir "$work/stubs" "$work/bin"
    # Every analyzer intake.sh looks for, as a stub that prints its arguments and succeeds, so
    # results don't depend on what the host has installed. timeout/gtimeout stay real.
    for t in gh go gofmt gopls staticcheck golangci-lint gosec govulncheck dupl checklocks errcheck nilaway \
      deadcode apidiff gitleaks trufflehog detect-secrets semgrep osv-scanner trivy grype jscpd pmd ast-grep \
      shellcheck node npm pnpm yarn opa conftest buf sqlfluff helm kubectl terraform tofu tflint hadolint \
      cargo cargo-audit cargo-deny rust-analyzer python3 ruff mypy pytest bandit pip-audit ansible-lint \
      yamllint kubeconform kube-linter kustomize checkov actionlint zizmor; do
      printf '#!/bin/sh\necho "STUB %s $*"\n' "$t" >"$work/stubs/$t"
      chmod +x "$work/stubs/$t"
    done
    for t in git pwsh rg jq; do ln -s "$(command -v "$t")" "$work/bin/$t"; done
    PATH=$work/stubs:$work/bin:/usr/bin:/bin sh "$here/suite.sh" host "$skill" "$work"
    ;;
  container)
    command -v docker >/dev/null 2>&1 || die "docker is required"
    image=${IMAGE:-ardan-pr-review-tools}
    [ "${NO_BUILD-}" = 1 ] || docker build -q -t "$image" "$here" >/dev/null
    docker run --rm -e "UPDATE=${UPDATE-}" -v "$skill:/skill:ro" -v "$here:/tests" "$image" \
      sh -c 'w=$(mktemp -d) && sh /tests/suite.sh container /skill "$w"'
    ;;
  *) die "usage: run.sh host|container" ;;
esac
