# Every analyzer the ardan-pr-review checks scripts can run, at pinned versions, plus PowerShell
# for the PowerShell port. Builds for amd64 and arm64. Bump a version deliberately, re-run
# `make test-pr-review`, and update expected/ if the change in results is intended.
FROM golang:1.27.3-bookworm

ARG UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:157.0) Gecko/20100101 Firefox/157.0"
ARG TARGETARCH
ARG PWSH_VERSION=7.6.9
ARG HADOLINT_VERSION=2.15.1
ARG TERRAFORM_VERSION=1.17.1
ARG TOFU_VERSION=1.13.2
ARG TFLINT_VERSION=0.65.0
ARG HELM_VERSION=4.3.1
ARG TRIVY_VERSION=0.76.1
ARG KUBECONFORM_VERSION=0.8.0
ARG KUBE_LINTER_VERSION=0.8.3
ARG ACTIONLINT_VERSION=1.7.12
ARG KUSTOMIZE_VERSION=5.8.3
ARG GITLEAKS_VERSION=8.30.1
ARG STATICCHECK_VERSION=0.8.2
ARG GOVULNCHECK_VERSION=1.9.0
ARG GOSEC_VERSION=2.30.0
ARG DUPL_VERSION=1.1.0
ARG ERRCHECK_VERSION=1.30.0
ARG NILAWAY_VERSION=v0.0.0-20260918162853-acb8859b9031
ARG XTOOLS_VERSION=0.52.0
ARG XEXP_VERSION=v0.0.0-20261014143641-f0251eb4aa3e
ARG CHECKLOCKS_VERSION=v0.0.0-20261103030936-1899f71d79be
ARG RUST_VERSION=1.99.1
ARG CARGO_AUDIT_VERSION=0.22.2
ARG CARGO_DENY_VERSION=0.20.2
ARG RUFF_VERSION=0.17.3
ARG MYPY_VERSION=2.4.1
ARG PYTEST_VERSION=9.2.0
ARG BANDIT_VERSION=1.9.4
ARG PIP_AUDIT_VERSION=2.10.1
ARG ANSIBLE_LINT_VERSION=26.10.1
ARG YAMLLINT_VERSION=1.38.0
ARG ZIZMOR_VERSION=1.32.0

ENV PATH=/root/.cargo/bin:/root/.local/bin:/root/go/bin:/opt/pwsh:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
      jq ripgrep shellcheck python3 python3-venv pipx unzip ca-certificates curl coreutils libicu72 \
    && rm -rf /var/lib/apt/lists/*

# Release binaries. "a" is the Debian arch (amd64/arm64); some projects spell it differently.
RUN a=${TARGETARCH:-$(dpkg --print-architecture)}; p=$( [ "$a" = amd64 ] && echo x64 || echo arm64 ) \
    && mkdir -p /opt/pwsh \
    && curl -fsSL --retry 5 --retry-all-errors -A "$UA" "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-$p.tar.gz" | tar -xz -C /opt/pwsh \
    && chmod +x /opt/pwsh/pwsh
RUN a=${TARGETARCH:-$(dpkg --print-architecture)}; h=$( [ "$a" = amd64 ] && echo x86_64 || echo arm64 ) \
    && curl -fsSL --retry 5 --retry-all-errors -A "$UA" -o /usr/local/bin/hadolint "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-$h" \
    && chmod +x /usr/local/bin/hadolint
RUN a=${TARGETARCH:-$(dpkg --print-architecture)} \
    && curl -fsSL --retry 5 --retry-all-errors -A "$UA" -o /tmp/tf.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_$a.zip" \
    && unzip -q -o /tmp/tf.zip terraform -d /usr/local/bin && rm /tmp/tf.zip
RUN a=${TARGETARCH:-$(dpkg --print-architecture)} \
    && curl -fsSL --retry 5 --retry-all-errors -A "$UA" -o /tmp/tofu.zip "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_$a.zip" \
    && unzip -q -o /tmp/tofu.zip tofu -d /usr/local/bin && rm /tmp/tofu.zip
RUN a=${TARGETARCH:-$(dpkg --print-architecture)} \
    && curl -fsSL --retry 5 --retry-all-errors -A "$UA" -o /tmp/tflint.zip "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_$a.zip" \
    && unzip -q -o /tmp/tflint.zip -d /usr/local/bin && rm /tmp/tflint.zip
RUN a=${TARGETARCH:-$(dpkg --print-architecture)} \
    && curl -fsSL --retry 5 --retry-all-errors -A "$UA" "https://get.helm.sh/helm-v${HELM_VERSION}-linux-$a.tar.gz" | tar -xz -C /tmp \
    && mv "/tmp/linux-$a/helm" /usr/local/bin/
RUN a=${TARGETARCH:-$(dpkg --print-architecture)}; t=$( [ "$a" = amd64 ] && echo 64bit || echo ARM64 ) \
    && curl -fsSL --retry 5 --retry-all-errors -A "$UA" "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-$t.tar.gz" | tar -xz -C /usr/local/bin trivy
RUN a=${TARGETARCH:-$(dpkg --print-architecture)} \
    && curl -fsSL --retry 5 --retry-all-errors -A "$UA" "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-$a.tar.gz" | tar -xz -C /usr/local/bin kubeconform

# Go-built tools, one step each.
RUN go install golang.stackrox.io/kube-linter/cmd/kube-linter@v${KUBE_LINTER_VERSION} && go clean -cache
RUN go install github.com/rhysd/actionlint/cmd/actionlint@v${ACTIONLINT_VERSION} && go clean -cache
RUN go install sigs.k8s.io/kustomize/kustomize/v5@v${KUSTOMIZE_VERSION} && go clean -cache
RUN go install github.com/zricethezav/gitleaks/v8@v${GITLEAKS_VERSION} && go clean -cache
RUN go install honnef.co/go/tools/cmd/staticcheck@v${STATICCHECK_VERSION} \
 && go install golang.org/x/vuln/cmd/govulncheck@v${GOVULNCHECK_VERSION} \
 && go install github.com/securego/gosec/v2/cmd/gosec@v${GOSEC_VERSION} \
 && go install github.com/mibk/dupl@v${DUPL_VERSION} \
 && go install github.com/kisielk/errcheck@v${ERRCHECK_VERSION} \
 && go install go.uber.org/nilaway/cmd/nilaway@${NILAWAY_VERSION} \
 && go install golang.org/x/tools/cmd/deadcode@v${XTOOLS_VERSION} \
 && go install golang.org/x/exp/cmd/apidiff@${XEXP_VERSION} \
 && go install gvisor.dev/gvisor/tools/checklocks/cmd/checklocks@${CHECKLOCKS_VERSION} \
 && go clean -cache

# Python tools, each isolated.
RUN pipx install "ruff==${RUFF_VERSION}" && pipx install "mypy==${MYPY_VERSION}" \
 && pipx install "pytest==${PYTEST_VERSION}" && pipx install "bandit==${BANDIT_VERSION}" \
 && pipx install "pip-audit==${PIP_AUDIT_VERSION}" && pipx install "ansible-lint==${ANSIBLE_LINT_VERSION}" \
 && pipx install "yamllint==${YAMLLINT_VERSION}" && pipx install "zizmor==${ZIZMOR_VERSION}"

# Rust toolchain + audit tools.
RUN curl -fsSL --retry 5 --retry-all-errors -A "$UA" https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "${RUST_VERSION}" --component clippy,rustfmt \
 && cargo install --locked "cargo-audit@${CARGO_AUDIT_VERSION}" "cargo-deny@${CARGO_DENY_VERSION}" \
 && rm -rf /root/.cargo/registry/cache

RUN git config --global user.email test@example.com && git config --global user.name test \
 && git config --global init.defaultBranch main
WORKDIR /work
