#!/bin/sh
# Usage: sh checks.sh RUN_DIR [--env K=V]... [--exclude PATH]... [--timeout 15m] [--no-tests]
# Runs every mechanical check ONCE, scoped to the files/packages intake.sh recorded in
# RUN_DIR/context, in parallel. The depth comes from scope.txt: at diff depth file checks
# cover the changed files; at full depth (files/packages/project) they cover review-set.tsv,
# and Go checks cover packages.tsv, which intake fills to match the depth.
# Output: RUN_DIR/context/checks/<check>.txt (full log) and RUN_DIR/context/checks/summary.tsv
# (check status exit lines file). Prints the summary.
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
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

ctx=$(cd -- "$run/context" 2>/dev/null && pwd) || die "no context in $run (run intake.sh first)"
root=$(sed -n 's/^root=//p' "$ctx/scope.txt")
basesha=$(sed -n 's/^base=//p' "$ctx/scope.txt")
depth=$(sed -n 's/^depth=//p' "$ctx/scope.txt")
# scoped: the files under review — the changed files, or the review set at full depth
scoped=$ctx/files.tsv
[ "${depth:-diff}" = diff ] || scoped=$ctx/review-set.tsv
cd -- "$root" 2>/dev/null || die "cannot enter repo root $root"
out=$ctx/checks
mkdir -p "$out" || die "cannot create $out"
has() { grep -q "^$1	" "$ctx/tools.tsv"; }
toolpath() { awk -F '\t' -v t="$1" '$1 == t { print $2; exit }' "$ctx/tools.tsv"; }

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

# live LANG: reviewed (not deleted) files of LANG ("*" = any), repo-relative
live() { awk -F '\t' -v l="$1" '$1 != "D" && $5 != "generated" && $5 != "vendor" && (l == "*" || $4 == l) { print $7 }' "$scoped"; }

# --- base tree (apidiff, buf breaking) ---------------------------------------------------
# The base commit's files, extracted outside the repo with git archive: nothing is written
# to the working tree or .git. Removed when the script exits.
basesrc='' setcopy=''
trap '[ -z "$basesrc" ] || rm -rf "$basesrc"; [ -z "$setcopy" ] || rm -rf "$setcopy"' EXIT
protos=$(live proto)
bufcfg=0
{ [ -f buf.yaml ] || [ -f buf.work.yaml ]; } && bufcfg=1
if [ -n "$basesha" ] && { { [ -s "$ctx/packages.tsv" ] && has apidiff; } ||
  { [ -n "$protos" ] && [ $bufcfg = 1 ] && has buf; }; }; then
  if basesrc=$(mktemp -d); then
    git archive "$basesha" | tar -x -C "$basesrc" || { rm -rf "$basesrc"; basesrc=''; }
  else basesrc=''
  fi
fi

# apidiff_pkgs MODULE PKG...: incompatible exported-API changes of each package against
# the base tree. Runs in the head module directory. New, main, and internal packages skipped.
apidiff_pkgs() {
  m=$1; shift
  bmod=$basesrc/$m
  for p in "$@"; do
    [ -d "$bmod/$p" ] || continue
    ip=$(go list -f '{{if ne .Name "main"}}{{.ImportPath}}{{end}}' "$p" 2>/dev/null)
    case $ip in ''|*/internal|*/internal/*|internal/*) continue ;; esac
    ex=$basesrc/apidiff-$(printf '%s' "$ip" | tr '/' '_').export
    if ! (cd -- "$bmod" && apidiff -w "$ex" "$ip") >/dev/null 2>"$ex.err"; then
      printf '## %s: base export failed\n' "$ip"; sed -n 1,5p "$ex.err"; continue
    fi
    res=$(apidiff -incompatible "$ex" "$ip" 2>&1)
    [ -z "$res" ] || printf '## %s\n%s\n' "$ip" "$res"
  done
}

# deadcode_scoped: unreachable functions (tests count as roots) in the reviewed files of
# this module. $1 = module dir relative to the repo root.
deadcode_scoped() {
  m=$1
  pre=''; [ "$m" = . ] || pre=$m/
  log=$(mktemp) || return 1
  deadcode -test ./... >"$log" 2>&1
  rc=$?
  if [ $rc != 0 ]; then
    if grep -q 'no main packages' "$log"; then echo '# no main or test packages: nothing to analyze'; rc=0
    else cat "$log"
    fi
    rm -f "$log"; return $rc
  fi
  awk -v pre="$pre" -v files="$scoped" '
    BEGIN { while ((getline l < files) > 0) { split(l, f, "\t"); if (f[1] != "D") ch[f[7]] = 1 } }
    { p = $0; sub(/:[0-9]+:[0-9]+: .*/, "", p); sub(/^\.\//, "", p)
      if ((pre p) in ch || p in ch) print }' "$log"
  rm -f "$log"
}

# --- Go, per module ------------------------------------------------------------------
gominor=$(go env GOVERSION 2>/dev/null | sed -n 's/^go\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')
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
    elif [ -z "$testpkgs" ]; then skip "go-test$sfx" "all packages excluded"
    else job "go-test$sfx" go test -race -count=1 -timeout "$timeout" $testpkgs
    fi
    if ls .golangci.y*ml .golangci.toml .golangci.json >/dev/null 2>&1; then
      if has golangci-lint; then job "golangci-lint$sfx" golangci-lint run $pkgs
      else skip "golangci-lint$sfx" "golangci-lint not installed"
      fi
    fi
    if has staticcheck; then job "staticcheck$sfx" staticcheck $pkgs; else skip "staticcheck$sfx" "staticcheck not installed"; fi
    if has checklocks; then job "checklocks$sfx" go vet -vettool="$(toolpath checklocks)" $pkgs
    else skip "checklocks$sfx" "checklocks not installed"
    fi
    if has errcheck; then job "errcheck$sfx" errcheck $pkgs; else skip "errcheck$sfx" "errcheck not installed"; fi
    if has nilaway; then
      modpath=$(awk '$1 == "module" { gsub(/"/, "", $2); print $2; exit }' go.mod)
      job "nilaway$sfx" nilaway -pretty-print=false -include-pkgs="$modpath" $pkgs
    else skip "nilaway$sfx" "nilaway not installed"
    fi
    if has deadcode; then job "deadcode$sfx" deadcode_scoped "$m"; else skip "deadcode$sfx" "deadcode not installed"; fi
    if ! has apidiff; then skip "apidiff$sfx" "apidiff not installed"
    elif [ -z "$basesrc" ]; then skip "apidiff$sfx" "base commit not available locally"
    else job "apidiff$sfx" apidiff_pkgs "$m" $pkgs
    fi
    # shellcheck disable=SC2086 # "major minor"
    set -- $gominor
    if [ $# = 2 ] && { [ "$1" -gt 1 ] || [ "$2" -ge 26 ]; }; then job "go-fix$sfx" go fix -diff $pkgs
    else skip "go-fix$sfx" "go fix modernizers need Go 1.26+"
    fi
    job "go-mod-tidy$sfx" go mod tidy -diff
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

# --- reviewed files by language ------------------------------------------------------
go_files=$(live go)
if [ -n "$go_files" ] && has go; then
  # shellcheck disable=SC2086
  job gofmt gofmt -l $go_files
fi

if [ -n "$protos" ]; then
  if [ $bufcfg = 0 ]; then skip buf-lint "no buf.yaml/buf.work.yaml at the repo root"
  elif ! has buf; then skip buf-lint "buf not installed"
  else
    set --
    for p in $protos; do set -- "$@" --path "$p"; done
    job buf-lint buf lint "$@"
    if [ -n "$basesrc" ]; then job buf-breaking buf breaking --against "$basesrc"
    else skip buf-breaking "base commit not available locally"
    fi
  fi
fi

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

# Secrets: the reviewed diff, or at full depth a copy of the review set (so generated and
# vendored files stay out; findings show repo-relative paths). generated.patch is scanned
# only on request, by the generated-scan agent (see references/roles/generated-scan.md).
if has gitleaks && [ "$scoped" != "$ctx/files.tsv" ]; then
  if setcopy=$(mktemp -d); then
    # Never follow a symlink out of the repo (intake already leaves them out of the set).
    live '*' | while IFS= read -r f; do
      [ -L "$f" ] && continue
      mkdir -p "$setcopy/$(dirname -- "$f")" && cp -P -p -- "$f" "$setcopy/$f"
    done
    if gitleaks help dir >/dev/null 2>&1; then
      # shellcheck disable=SC2016 # $1 expands in the child shell
      job gitleaks sh -c 'cd "$1" && gitleaks dir -v --no-banner --redact .' _ "$setcopy"
    else
      # shellcheck disable=SC2016
      job gitleaks sh -c 'cd "$1" && gitleaks detect -v --no-git --no-banner --redact --source .' _ "$setcopy"
    fi
  else setcopy=''; skip gitleaks "cannot create a temp copy of the review set"
  fi
elif has gitleaks; then
  if gitleaks help stdin >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # $1 expands in the child shell
    job gitleaks sh -c 'gitleaks stdin -v --no-banner --redact <"$1"' _ "$ctx/diff.patch"
  else
    job gitleaks gitleaks detect -v --no-git --no-banner --redact --source "$ctx/diff.patch"
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
  # These exit 0 and report through output: any line not starting with "#" is a hit.
  case $n in
    dupl*|gofmt|deadcode*|apidiff*)
      [ "$s" = pass ] && grep -q '^[^#]' "$out/$n.txt" && s=findings ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$s" "$e" "$(wc -l <"$out/$n.txt" | tr -d ' ')" "checks/$n.txt" >>"$out/summary.tsv"
  rm -f "$f"
done
cat "$out/summary.tsv"
