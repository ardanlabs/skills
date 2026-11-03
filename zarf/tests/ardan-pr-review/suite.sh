#!/bin/sh
# Usage: sh suite.sh MODE SKILL_DIR WORK_DIR
# Regression suite for the ardan-pr-review scripts; run.sh sets up MODE and calls this.
#   host       analyzers are stubs (run.sh puts them first on PATH): exercises the scripts with the
#              host's own sh/awk/sed (BSD on macOS, GNU on Linux) and PowerShell.
#   container  real analyzers at pinned versions (Dockerfile).
# Asserts: sh and PowerShell ports write identical context files and check results; intake and
# check results match expected/ (golden files); checks leave the working tree untouched.
# UPDATE=1 rewrites the golden files from this run instead of comparing. Exit: 0 pass | 1 fail.
set -u
mode=$1 skill=$2 work=$3
here=$(cd "$(dirname "$0")" && pwd)
sk=$skill/scripts exp=$here/expected
# No global or system git config: signing, hooks, or diff settings must not change results.
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
fails=0

say() { printf '%s\n' "$*"; }
fail() { say "FAIL  $*"; fails=$((fails + 1)); }
pass() { say "ok    $*"; }

# golden NAME FILE: FILE must equal expected/NAME (UPDATE=1: write it instead).
golden() {
  if [ "${UPDATE-}" = 1 ]; then mkdir -p "$exp" && cp "$2" "$exp/$1" && say "wrote expected/$1"; return; fi
  if [ ! -f "$exp/$1" ]; then fail "golden $1: expected/$1 missing (run with UPDATE=1)"; return; fi
  if diff -u "$exp/$1" "$2" >"$work/golden.diff" 2>&1; then pass "golden $1"
  else fail "golden $1"; sed -n '1,40s/^/      /p' "$work/golden.diff"
  fi
}

# scope_view FILE: scope.txt without host- or run-specific keys
scope_view() { grep -v -E '^(run|root|languages|missing_tools)=' "$1"; }

# parity_ctx A B LABEL: the context files written by the two ports must be identical.
parity_ctx() {
  bad=''
  for f in "$1"/*; do
    n=${f##*/}
    [ -f "$f" ] || continue
    case $n in
      scope.txt) scope_view "$f" >"$work/p1"; scope_view "$2/$n" >"$work/p2" 2>/dev/null ;;
      *) cp "$f" "$work/p1"; cp "$2/$n" "$work/p2" 2>/dev/null || : >"$work/p2" ;;
    esac
    cmp -s "$work/p1" "$work/p2" || { bad="$bad $n"; diff "$work/p1" "$work/p2" | sed -n '1,10s/^/      /p'; }
  done
  for f in "$2"/*; do [ -f "$f" ] && [ ! -e "$1/${f##*/}" ] && bad="$bad ${f##*/}(ps only)"; done
  if [ -z "$bad" ]; then pass "parity $3"; else fail "parity $3:$bad"; fi
}

# checks_view RUN: check, status, lens of a run's summary
checks_view() { cut -f1,2,6 "$1/context/checks/summary.tsv"; }

# tree_state: what git sees, ignoring the run directories and cargo's build output
tree_state() { git status --porcelain --ignored | grep -v -e '^!! \.reviews/' -e 'crates/core/target/' || true; }

# intake_pair ID SH_ARGS PS_ARGS: both ports into .reviews/sh and .reviews/ps
intake_pair() {
  # shellcheck disable=SC2086 # argument lists
  sh "$sk/intake.sh" --id "$1" --reviews-dir .reviews/sh $2 >"$work/intake-sh-$1.out" 2>&1 || fail "intake.sh $1 exit $?"
  # shellcheck disable=SC2086
  pwsh -NoProfile -File "$sk/intake.ps1" -Id "$1" -ReviewsDir .reviews/ps $3 >"$work/intake-ps-$1.out" 2>&1 || fail "intake.ps1 $1 exit $?"
  parity_ctx ".reviews/sh/$1/001/context" ".reviews/ps/$1/001/context" "intake $1"
}

# checks_pair ID [SH_ARGS] [PS_ARGS]: both ports' checks on the ID runs; summaries must agree
checks_pair() {
  # shellcheck disable=SC2086
  sh "$sk/checks.sh" ".reviews/sh/$1/001" ${2-} >"$work/checks-sh-$1.out" 2>&1 || fail "checks.sh $1 exit $?"
  # shellcheck disable=SC2086
  pwsh -NoProfile -File "$sk/checks.ps1" ".reviews/ps/$1/001" ${3-} >"$work/checks-ps-$1.out" 2>&1 || fail "checks.ps1 $1 exit $?"
  checks_view ".reviews/sh/$1/001" >"$work/c1"; checks_view ".reviews/ps/$1/001" >"$work/c2"
  if cmp -s "$work/c1" "$work/c2"; then pass "parity checks $1"
  else fail "parity checks $1"; diff "$work/c1" "$work/c2" | sed 's/^/      /'; tail -n 5 "$work/checks-ps-$1.out" | sed 's/^/      ps: /'
  fi
}

say "== ardan-pr-review suite ($mode)"
sh "$here/fixture.sh" "$work/fx" || { say "FAIL  fixture"; exit 1; }
cd "$work/fx" || exit 1
before=$(tree_state)

# --- intake: three depths, both ports, golden context ------------------------------------
intake_pair diff "--base main" "-Base main"
c=.reviews/sh/diff/001/context
for f in files.tsv skipped.tsv stack.tsv symbols.tsv refs.tsv unmapped.txt signals.txt packages.tsv; do golden "diff.$f" "$c/$f"; done
scope_view "$c/scope.txt" | grep -v -E '^(head|base)=' >"$work/scope.view"; golden diff.scope.txt "$work/scope.view"

intake_pair project "--base main --depth project" "-Base main -Depth project"
c=.reviews/sh/project/001/context
for f in review-set.tsv stack.tsv shards.tsv size.tsv; do [ -f "$c/$f" ] || : >"$c/$f"; golden "project.$f" "$c/$f"; done

intake_pair gen "--base main --depth packages --include-generated" "-Base main -Depth packages -IncludeGenerated"
c=.reviews/sh/gen/001/context
for f in files.tsv skipped.tsv review-set.tsv; do golden "gen.$f" "$c/$f"; done

# --- extract-findings: both modes, both ports ------------------------------------------------
mkdir -p "$work/ex/sh/context" "$work/ex/ps/context"
cat >"$work/ex/transcript.jsonl" <<'EOF'
{"text":"role file\n===== stack.md =====\nTEMPLATE\n===== end ====="}
{"text":"discovery: x\n===== stack.md =====\n# Stack\n- rust\n===== extra-checks.tsv =====\nlint\t.\tservice-steward\tmake lint\tMakefile:1\n===== end ====="}
{"text":"findings: G1\n===== findings.md =====\n# Service DiffGuard Report\nok\n===== end ====="}
EOF
if ! { sh "$sk/extract-findings.sh" --discovery "$work/ex/transcript.jsonl" "$work/ex/sh" >/dev/null &&
  sh "$sk/extract-findings.sh" "$work/ex/transcript.jsonl" "$work/ex/sh" >/dev/null; }; then fail "extract-findings.sh"; fi
if ! { pwsh -NoProfile -File "$sk/extract-findings.ps1" -Discovery "$work/ex/transcript.jsonl" "$work/ex/ps" >/dev/null &&
  pwsh -NoProfile -File "$sk/extract-findings.ps1" "$work/ex/transcript.jsonl" "$work/ex/ps" >/dev/null; }; then fail "extract-findings.ps1"; fi
if diff -r "$work/ex/sh" "$work/ex/ps" >/dev/null && [ "$(cat "$work/ex/sh/context/extra-checks.tsv")" = "$(printf 'lint\t.\tservice-steward\tmake lint\tMakefile:1')" ]; then
  pass "extract-findings (discovery + findings, both ports)"
else fail "extract-findings"; diff -r "$work/ex/sh" "$work/ex/ps" | sed 's/^/      /'
fi

# --- checks: both ports, golden statuses, read-only tree ----------------------------------------
printf 'echo-x\t.\tservice-steward\techo extra\tMakefile:1\nnot-approved\t.\t\techo no\tx\n' >"$work/extra.tsv"
cp "$work/extra.tsv" .reviews/sh/diff/001/context/extra-checks.tsv
cp "$work/extra.tsv" .reviews/ps/diff/001/context/extra-checks.tsv
checks_pair diff "--extra echo-x" "-Extra echo-x"
checks_view .reviews/sh/diff/001 >"$work/checks.view"; golden "$mode.checks.tsv" "$work/checks.view"
after=$(tree_state)
if [ "$before" = "$after" ]; then pass "working tree unchanged by checks"
else fail "working tree changed by checks"; printf '%s\n' "$after" | sed 's/^/      /'
fi

# --- container: OpenTofu selection and its read-only lock -------------------------------------
if [ "$mode" = container ]; then
  echo 1.13.0 >.opentofu-version
  intake_pair tofu "--base main" "-Base main"
  grep '^terraform' .reviews/sh/tofu/001/context/stack.tsv >"$work/tofu.stack"; golden tofu.stack.tsv "$work/tofu.stack"
  checks_pair tofu
  grep -E '^(tf|tflint)' "$work/c1" >"$work/tofu.view"; golden tofu.checks.tsv "$work/tofu.view"
  rm -f .opentofu-version
  after=$(tree_state)
  if [ "$before" = "$after" ]; then pass "working tree unchanged by OpenTofu checks"
  else fail "working tree changed by OpenTofu checks"; printf '%s\n' "$after" | sed 's/^/      /'
  fi
fi

if [ $fails -gt 0 ]; then say "== $fails failure(s); logs and runs in $work"; exit 1; fi
say "== all passed"
