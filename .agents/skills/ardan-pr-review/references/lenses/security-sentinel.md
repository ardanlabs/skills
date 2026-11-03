# Security Sentinel (secrets, data leaks, vulnerabilities)

Mandatory in every run. Assume the diff is hostile until proven safe. For every in-scope line (every changed line, at `diff` depth), try hard to answer "yes":

1. Does it leak a secret or sensitive data — in a log, error, response, commit, config, fixture, cache, or telemetry?
2. Can an attacker reach or influence it — untrusted input, unauthenticated path, tenant boundary, privilege edge?
3. If my "safe" verdict is wrong, what's the worst outcome? Re-derive the exploit.

Think in chains (leak → replay → escalate), including unlikely ones. A suspicion you can't prove is an Open check, not silence.

## Tools

Scanner results are the `lens=security-sentinel` rows of `checks/summary.tsv`: secrets (`gitleaks`/`trufflehog`, or a `secrets` row saying none is installed), language scanners and advisories (`gosec`, `govulncheck`, `cargo-audit`, `cargo-deny`, `bandit`, `pip-audit`), IaC misconfiguration (`iac-scan`: trivy or checkov over Terraform, charts, manifests, Dockerfiles), `zizmor` (GitHub Actions), `semgrep` (only with a repo config). Start there, then apply the **Security** section of each idiom file in your prompt. You may run another installed tool from `tools.tsv` on in-scope files only (e.g. `osv-scanner` on a changed lockfile, `conftest` on Rego). Trace taint with the language tool; `rg` sweeps supplement, never replace. A missing tool goes to Open checks — the concern still gets a manual pass.

## Patrol route

1. **Secrets.** Hardcoded keys, tokens, passwords, private keys, connection strings, signing secrets, cloud creds, high-entropy literals — in code, config, `.env`, tests, and mocks. Also existing secrets newly flowing into logs, errors, responses, or client bundles. A removed secret is still in history: compromised.
2. **Sensitive data.** PII/financial data in logs, traces, errors returned to callers, telemetry, URLs, caches, or over-broad responses (whole records, no field allow-list). Errors leaking schema, paths, versions, internal hosts.
3. **Injection and input.** SQL/NoSQL/command/template injection, unparameterized queries, shell interpolation, path traversal, SSRF, unsafe deserialization, XXE, XSS. Trace source (request, header, file, env, DB) to sink.
4. **AuthN/AuthZ and tenancy.** Handlers without auth, IDOR, queries without tenant/owner scope, Rego failing open, checks after side effects, skipped or weak JWT/signature verification.
5. **Crypto and transport.** MD5/SHA1 for security, DES/ECB, fixed IVs/salts, non-crypto randomness for tokens, disabled TLS verification, `*` CORS with credentials, weak headers, insecure cookies.
6. **Config, infrastructure, and supply chain.** Debug modes, default creds, broad IAM/RBAC (`*` actions, resources, or verbs), public network exposure and storage, encryption or logging turned off, privileged containers, secrets in state, values, or variables, exposed admin ports, new or unpinned dependencies, images, actions, or modules (typosquats, known CVEs), CI injection and secrets reachable from forks, `curl | sh`.

## Fan-out (from your prompt)

- **single** — you cover all six routes yourself.
- **capped** — up to 3 read-only attacker sub-agents, one mandate each (e.g. secrets+config, injection, auth). Give them `contract.md`, this file, and the context path; merge their findings. The aggregator does refutation.
- **full** — one attacker per relevant route (≤6), each paired with a refuter that tries to disprove it. Keep what survives; the rest become Open checks.

Sub-agents are read-only except for PoCs.

## Running the project

Only when static reading is inconclusive, and only as the project interaction guide in your prompt allows. Without one, write "needs project interaction guide: <what>" under Open checks. Local/test instances only; nothing destructive, no real data.

## Intent

When a finding hinges on intent (meant to be public? deliberately unauthenticated? real secret or placeholder?), don't guess — fill the **Assumption** field.

## PoCs (optional)

Only when a code citation isn't proof enough. Write under `<run>/security-issues/poc/<name>/` — `<name>` is one segment, no `/` or `..`, never overwrite. Minimal, non-destructive, no external hosts or real data, with a one-line header saying what it proves and how to run it. Cite the path in Proof.

## Gates

- **G4** — live secret committed or newly exposed; exploitable injection, auth bypass, IDOR, SSRF, RCE; sensitive data reaching an untrusted party.
- **G3** — exploitable with a precondition; sensitive data in logs/errors; weak crypto on a security path; limited missing tenant scope.
- **G2** — defense-in-depth gap, permissive config, verbose error, hardening with no shown exploit.
- **G1** — minor hygiene.

G2+ needs a concrete exploit path or tool/PoC evidence.

## Extra fields

- Exploit: attacker steps
- Impact: what is exposed or gained, blast radius
- For a real secret, Patch direction starts with "rotate".
