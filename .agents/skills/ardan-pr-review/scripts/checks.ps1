# Usage: checks.ps1 RUN_DIR [-Env K=V,...] [-Exclude PATH,...] [-Timeout 15m] [-NoTests]
# PowerShell port of checks.sh (same outputs). Runs every mechanical check ONCE, scoped to the
# files/packages intake recorded in RUN_DIR/context, in parallel. Output:
# RUN_DIR/context/checks/<check>.txt (full log) and RUN_DIR/context/checks/summary.tsv.
#   -Env K=V      set for every check (e.g. GITHUB_WORKSPACE=C:\repo)
#   -Exclude PATH never run tests in packages under PATH (repo-relative)
#   -Timeout D    go test -timeout (default 15m)
#   -NoTests      skip test runs
# A failing check is data for the reviewers, not a script failure. Exit: 0 ran | 2 usage.
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$RunDir,
    [string[]]$Env = @(),
    [string[]]$Exclude = @(),
    [string]$Timeout = '15m',
    [switch]$NoTests
)

# -File passes 'a,b' as one string: split list parameters ourselves (-Env only before NAME=).
$Env = @($Env | ForEach-Object { $_ -split ',(?=[A-Za-z_][A-Za-z0-9_]*=)' } | Where-Object { $_ })
$Exclude = @($Exclude | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$utf8 = [Text.UTF8Encoding]::new($false)
function Die([string]$msg) { [Console]::Error.WriteLine("checks: $msg"); exit 2 }
function Out-Text([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }
function ReadTsv([string]$path) { if (Test-Path -LiteralPath $path) { @([IO.File]::ReadAllLines($path) | Where-Object { $_ } | ForEach-Object { , ($_ -split "`t") }) } else { @() } }

$ctxItem = Get-Item -LiteralPath (Join-Path $RunDir 'context') -ErrorAction SilentlyContinue
if (-not $ctxItem) { Die "no context in $RunDir (run intake first)" }
$ctx = $ctxItem.FullName
$root = ([IO.File]::ReadAllLines((Join-Path $ctx 'scope.txt')) | Where-Object { $_.StartsWith('root=') } | Select-Object -First 1).Substring(5)
if (-not (Test-Path -LiteralPath $root -PathType Container)) { Die "cannot enter repo root $root" }
Set-Location -LiteralPath $root
$out = Join-Path $ctx 'checks'
New-Item -ItemType Directory -Path $out -Force | Out-Null

$envKeys = foreach ($kv in $Env) {
    if ($kv -cnotmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { Die "bad -Env '$kv' (need K=V)" }
    [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2]); $Matches[1]
}
$Exclude = @($Exclude | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('/') })
$tests = -not $NoTests
Out-Text (Join-Path $out 'setup.txt') ("env_keys=$(@($envKeys) -join ' ')`ntest_excludes=$(($Exclude | ForEach-Object { "$_ " }) -join '')`ntest_timeout=$Timeout`ntests=$([int]$tests)`n")

$tools = @{}; foreach ($r in @(ReadTsv (Join-Path $ctx 'tools.tsv'))) { $tools[$r[0]] = $r[1] }
function Has([string]$t) { $tools.ContainsKey($t) }

$jobs = New-Object System.Collections.Generic.List[object]
$runner = {
    param([string]$dir, [string]$log, [string]$exe, [string[]]$a, [string[]]$stdin)
    Set-Location -LiteralPath $dir
    $enc = [Text.UTF8Encoding]::new($false)
    $head = "# cmd: $exe $($a -join ' ')`n"
    try {
        if ($stdin) {
            $text = ($stdin | ForEach-Object { [IO.File]::ReadAllText($_) }) -join ''
            $res = $text | & $exe @a 2>&1
        } else {
            $res = & $exe @a 2>&1
        }
        $code = $LASTEXITCODE
    } catch { $res = @("$_"); $code = 127 }
    $body = (@($res) | ForEach-Object { "$_" }) -join "`n"
    if ($body) { $body += "`n" }
    [IO.File]::WriteAllText($log, $head + $body, $enc)
    [IO.File]::WriteAllText(($log -replace '\.txt$', '.exit'), "$code", $enc)
}
function Job([string]$name, [string]$dir, [string]$exe, [string[]]$a, [string[]]$stdin = @()) {
    $jobs.Add((Start-Job -ScriptBlock $runner -ArgumentList $dir, (Join-Path $out "$name.txt"), $exe, $a, $stdin))
}
function Skip([string]$name, [string]$why) {
    Out-Text (Join-Path $out "$name.txt") "# skipped: $why`n"
    Out-Text (Join-Path $out "$name.exit") 'skip'
}

# --- Go, per module ------------------------------------------------------------------
$pk = @(ReadTsv (Join-Path $ctx 'packages.tsv'))
$modules = @($pk | ForEach-Object { $_[0] } | Select-Object -Unique)
foreach ($m in $modules) {
    $sfx = if ($modules.Count -gt 1) { '@' + ($m -creplace '/', '_') } else { '' }
    $dir = (Resolve-Path -LiteralPath $m).Path
    $pkgs = @($pk | Where-Object { $_[0] -ceq $m } | ForEach-Object { $_[1] })
    $testPkgs = @(foreach ($p in $pkgs) {
            $full = $p -creplace '^\./', ''
            if ($m -ne '.') { $full = "$m/$full" -creplace '/\.$', '' }
            if ($full -eq '.') { $full = '' }
            $ex = $false
            foreach ($e in $Exclude) { if ($full -ceq $e -or $full.StartsWith("$e/", [StringComparison]::Ordinal)) { $ex = $true } }
            if (-not $ex) { $p }
        })
    Job "go-build$sfx" $dir 'go' (@('build') + $pkgs)
    Job "go-vet$sfx" $dir 'go' (@('vet') + $pkgs)
    if (-not $tests) { Skip "go-test$sfx" '--no-tests' }
    elseif (-not $testPkgs.Count) { Skip "go-test$sfx" 'all changed packages excluded' }
    else { Job "go-test$sfx" $dir 'go' (@('test', '-count=1', '-timeout', $Timeout) + $testPkgs) }
    $golangciCfg = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -cmatch '^\.golangci\.(ya?ml|toml|json)$' })
    if ((Has 'golangci-lint') -and $golangciCfg.Count) { Job "golangci-lint$sfx" $dir 'golangci-lint' (@('run') + $pkgs) }
    elseif (Has 'staticcheck') { Job "staticcheck$sfx" $dir 'staticcheck' $pkgs }
    else { Skip "staticcheck$sfx" 'staticcheck/golangci-lint not installed' }
    if (Has 'gosec') { Job "gosec$sfx" $dir 'gosec' (@('-quiet') + $pkgs) } else { Skip "gosec$sfx" 'gosec not installed' }
    if (Has 'govulncheck') { Job "govulncheck$sfx" $dir 'govulncheck' $pkgs } else { Skip "govulncheck$sfx" 'govulncheck not installed' }
    if (Has 'dupl') { Job "dupl$sfx" $dir 'dupl' (@('-t', '50', '-plumbing') + $pkgs) } else { Skip "dupl$sfx" 'dupl not installed' }
}

# --- changed files by language -------------------------------------------------------
$files = @(ReadTsv (Join-Path $ctx 'files.tsv'))
function Live([string]$lang) { @($files | Where-Object { $_[0] -ne 'D' -and ($lang -eq '*' -or $_[3] -ceq $lang) } | ForEach-Object { $_[6] }) }

$sh = @(Live 'sh')
if ($sh.Count) {
    if (Has 'shellcheck') { Job 'shellcheck' $root 'shellcheck' $sh } else { Skip 'shellcheck' 'shellcheck not installed' }
}
$jsDirs = @(@(Live 'js') + @(Live 'ts') + @(Live 'vue') | ForEach-Object { $_ -creplace '/[^/]*$', '' } | Select-Object -Unique)
if ($jsDirs.Count -and (Has 'jscpd')) { Job 'jscpd' $root 'jscpd' (@('--min-tokens', '50', '--reporters', 'console', '--silent') + $jsDirs) }

# Secrets: the reviewed diff only. generated.patch is scanned only on request, by the
# generated-scan agent (see references/roles/generated-scan.md).
$patches = @(Join-Path $ctx 'diff.patch')
if (Has 'gitleaks') {
    & gitleaks help stdin *> $null
    if ($LASTEXITCODE -eq 0) { Job 'gitleaks' $root 'gitleaks' @('stdin', '--no-banner', '--redact') $patches }
    else { Job 'gitleaks' $root 'gitleaks' @('detect', '--no-git', '--no-banner', '--redact', '--source', $patches[0]) }
} elseif (Has 'trufflehog') {
    Job 'trufflehog' $root 'trufflehog' (@('filesystem', '--no-update') + @(Live '*'))
} else {
    Skip 'secrets' 'no secret scanner (gitleaks/trufflehog) installed'
}

$semcfg = @('.semgrep.yml', '.semgrep.yaml', '.semgrep') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ((Has 'semgrep') -and $semcfg) { Job 'semgrep' $root 'semgrep' (@('scan', '--metrics=off', '--config', $semcfg) + @(Live '*')) }

if ($jobs.Count) { $jobs | Wait-Job | Out-Null; $jobs | Receive-Job -ErrorAction SilentlyContinue | Out-Null; $jobs | Remove-Job }

# --- summary ----------------------------------------------------------------------------
$rows = New-Object System.Collections.Generic.List[string]
$rows.Add("check`tstatus`texit`tlines`tfile")
$names = [string[]]@(Get-ChildItem -LiteralPath $out -Filter '*.exit' | ForEach-Object { $_.Name })
[Array]::Sort($names, [StringComparer]::Ordinal)
foreach ($nm in $names) {
    $f = Join-Path $out $nm; $n = $nm -creplace '\.exit$', ''; $e = [IO.File]::ReadAllText($f).Trim()
    $s = switch ($e) { 'skip' { 'skipped' } '0' { 'pass' } default { 'fail' } }
    $log = Join-Path $out "$n.txt"
    $lines = 0; foreach ($x in [IO.File]::ReadLines($log)) { $lines++ }
    if ($n -cmatch '^dupl' -and $lines -gt 1) { $s = 'findings' }
    $rows.Add("$n`t$s`t$e`t$lines`tchecks/$n.txt")
    Remove-Item -LiteralPath $f
}
Out-Text (Join-Path $out 'summary.tsv') (($rows -join "`n") + "`n")
$rows
