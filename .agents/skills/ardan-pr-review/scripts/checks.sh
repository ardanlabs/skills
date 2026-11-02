#!/bin/sh
# Usage: sh checks.sh RUN_DIR [--env K=V]... [--exclude PATH]... [--timeout 15m] [--no-tests]
# Runs every mechanical check ONCE, scoped to the files/packages intake.sh recorded in
# RUN_DIR/context, in parallel. Output: RUN_DIR/context/checks/<check>.txt (full log) and
# RUN_DIR/context/checks/summary.tsv (check status exit lines file). Prints the summary.
#   --env K=V      exported for every check (e.g. GITHUB_WORKSPACE=/repo); repeatable
#   --exclude PATH never run tests in packages under PATH (repo-relative); repeatable
#   --timeout D    go test -timeout (default 15m)
#   --no-tests     skip test runs
# A failing check is data for the reviewers, not a script failure. Exit: 0 ran | 2 usage.

set -u

die() { echo "checks: $*" >&2; exit 2; }

[ $# -gt 0 ] || die "RUN_DIR required"
run=$1; shift
excludes='' timeout=15m tests=1 envkeys=''
while [ $# -gt 0 ]; do
  case $1 in
    --env)
      kv=${2-}; k=${kv%%=*}
      case $k in ''|[0-9]*|*[!A-Za-z0-9_]*) die "bad --env '$kv'" ;; esac
      [ "$k" != "$kv" ] || die "--env needs K=V"
      # shellcheck disable=SC2163 # exports the K=V pair itself
      export "$kv"; envkeys="$envkeys $k"; shift 2 ;;
    --exclude) excludes="$excludes${2%/}
"; shift 2 ;;
    --timeout) timeout=${2-}; shift 2 ;;
    --no-tests) tests=0; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

ctx=$(cd -- "$run/context" 2>/dev/null && pwd) || die "no context in $run (run intake.sh first)"
root=$(sed -n 's/^root=//p' "$ctx/scope.txt")
cd -- "$root" 2>/dev/null || die "cannot enter repo root $root"
out=$ctx/checks
mkdir -p "$out" || die "cannot create $out"
has() { grep -q "^$1	" "$ctx/tools.tsv"; }

{
  echo "env_keys=${envkeys# }"
  printf 'test_excludes=%s\n' "$(printf '%s' "$excludes" | tr '\n' ' ')"
  echo "test_timeout=$timeout"
  echo "tests=$tests"
} >"$out/setup.txt"

# job NAME CMD...: run CMD in the background, log to $out/NAME.txt, exit code to NAME.exit.
job() {
  name=$1; shift
  (
    printf '# cmd: %s\n' "$*"
    "$@" 2>&1
    echo $? >"$out/$name.exit"
  ) >"$out/$name.txt" 2>&1 &
}
skip() { printf '# skipped: %s\n' "$2" >"$out/$1.txt"; echo skip >"$out/$1.exit"; }

# --- Go, per module ------------------------------------------------------------------
modules=$(cut -f1 "$ctx/packages.tsv" | sort -u)
nmod=$(printf '%s\n' "$modules" | grep -c .)
for m in $modules; do
  sfx=''
  [ "$nmod" -gt 1 ] && sfx="@$(printf '%s' "$m" | tr '/' '_')"
  pkgs=$(awk -F '\t' -v m="$m" '$1 == m { print $2 }' "$ctx/packages.tsv")
  testpkgs=''
  for p in $pkgs; do
    full=${p#./}; [ "$m" = . ] || full=$m/${p#./}; [ "$full" = . ] && full=''
    ex=0
    for e in $excludes; do
      case $full in "$e"|"$e"/*) ex=1 ;; esac
    done
    [ $ex = 1 ] || testpkgs="$testpkgs $p"
  done
  # shellcheck disable=SC2086 # package lists are space-separated by design
  (
    cd -- "$m" || exit 1
    job "go-build$sfx" go build $pkgs
    job "go-vet$sfx" go vet $pkgs
    if [ $tests = 0 ]; then skip "go-test$sfx" "--no-tests"
    elif [ -z "$testpkgs" ]; then skip "go-test$sfx" "all changed packages excluded"
    else job "go-test$sfx" go test -count=1 -timeout "$timeout" $testpkgs
    fi
    if has golangci-lint && ls .golangci.y*ml .golangci.toml .golangci.json >/dev/null 2>&1; then
      job "golangci-lint$sfx" golangci-lint run $pkgs
    elif has staticcheck; then job "staticcheck$sfx" staticcheck $pkgs
    else skip "staticcheck$sfx" "staticcheck/golangci-lint not installed"
    fi
    if has gosec; then job "gosec$sfx" gosec -quiet $pkgs; else skip "gosec$sfx" "gosec not installed"; fi
    if has govulncheck; then job "govulncheck$sfx" govulncheck $pkgs; else skip "govulncheck$sfx" "govulncheck not installed"; fi
    if has dupl; then
      dirs=$(printf '%s\n' $pkgs)
      job "dupl$sfx" dupl -t 50 -plumbing $dirs
    else skip "dupl$sfx" "dupl not installed"
    fi
    wait
  ) &
done

# --- changed files by language -------------------------------------------------------
live() { awk -F '\t' -v l="$1" '$1 != "D" && $5 != "generated" && $5 != "vendor" && (l == "*" || $4 == l) { print $7 }' "$ctx/files.tsv"; }

sh_files=$(live sh)
if [ -n "$sh_files" ]; then
  if has shellcheck; then
    # shellcheck disable=SC2086
    job shellcheck shellcheck $sh_files
  else skip shellcheck "shellcheck not installed"
  fi
fi

js_dirs=$( { live js; live ts; live vue; } | sed 's|/[^/]*$||' | sort -u)
if [ -n "$js_dirs" ] && has jscpd; then
  # shellcheck disable=SC2086
  job jscpd jscpd --min-tokens 50 --reporters console --silent $js_dirs
fi

# Secrets: the reviewed diff only. generated.patch is scanned only on request, by the
# generated-scan agent (see references/roles/generated-scan.md).
if has gitleaks; then
  if gitleaks help stdin >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # $1 expands in the child shell
    job gitleaks sh -c 'gitleaks stdin --no-banner --redact <"$1"' _ "$ctx/diff.patch"
  else
    job gitleaks gitleaks detect --no-git --no-banner --redact --source "$ctx/diff.patch"
  fi
elif has trufflehog; then
  # shellcheck disable=SC2046
  job trufflehog trufflehog filesystem --no-update $(live '*')
else
  skip secrets "no secret scanner (gitleaks/trufflehog) installed"
fi

semcfg=''
for c in .semgrep.yml .semgrep.yaml .semgrep; do [ -e "$c" ] && semcfg=$c && break; done
if has semgrep && [ -n "$semcfg" ]; then
  # shellcheck disable=SC2046
  job semgrep semgrep scan --metrics=off --config "$semcfg" $(live '*')
fi

wait

# --- summary ----------------------------------------------------------------------------
printf 'check\tstatus\texit\tlines\tfile\n' >"$out/summary.tsv"
for f in "$out"/*.exit; do
  [ -e "$f" ] || continue
  n=${f##*/}; n=${n%.exit}; e=$(cat "$f")
  case $e in skip) s=skipped ;; 0) s=pass ;; *) s=fail ;; esac
  # dupl/jscpd/gitleaks report through output or non-zero exit; any duplicate line is a hit
  case $n in dupl*) [ -s "$out/$n.txt" ] && [ "$(wc -l <"$out/$n.txt")" -gt 1 ] && s=findings ;; esac
  printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$s" "$e" "$(wc -l <"$out/$n.txt" | tr -d ' ')" "checks/$n.txt" >>"$out/summary.tsv"
  rm -f "$f"
done
cat "$out/summary.tsv"
