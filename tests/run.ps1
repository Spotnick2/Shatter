<#
    run.ps1 - Run all Shatter unit tests.

    The tests are plain Lua 5.1 scripts (no dependencies). WoW uses Lua 5.1,
    so the tests do too, not the newer Lua that may be first on PATH. The
    scaffolding is WowTestKit at the commit tests\kit.pin names: this puts it
    in %LOCALAPPDATA%\WowTestKit\<sha> and hands off to the kit's runner
    (every tests\test_*.lua, one process each).

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -KitDev     # against the ..\WowTestKit working copy, not the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Lua)) {
    Write-Error "Lua 5.1 interpreter not found at: $Lua  (pass -Lua <path>)"
    exit 1
}

$RepoRoot = Split-Path -Parent $PSScriptRoot

# Run from the repo root so the tests can dofile('tests/...') and read
# Shatter.toc with paths relative to the project.
Push-Location $RepoRoot
try {
    # Syntax-check every Lua file in the repo (shipped, tests, tools), not
    # only the TOC's. A missing luac must fail the run: no test loads every
    # file, so skipping this would let a syntax error through behind a green
    # result.
    $luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
    if (-not (Test-Path $luac)) {
        Write-Error "luac.exe not found next to $Lua; the syntax check cannot run."
        exit 1
    }
    $sources = Get-ChildItem -Recurse -Filter "*.lua" -File |
        Where-Object { $_.FullName -notmatch '\\\.git\\' } |
        ForEach-Object { Resolve-Path -Relative $_.FullName }
    if ($sources.Count -eq 0) { Write-Error "no Lua files found"; exit 1 }
    & $luac -p @sources
    if ($LASTEXITCODE -ne 0) {
        Write-Host "luac -p FAILED" -ForegroundColor Red
        exit 1
    }
    Remove-Item -LiteralPath (Join-Path $RepoRoot "luac.out") -ErrorAction SilentlyContinue
    Write-Host "luac -p: ok ($($sources.Count) files)" -ForegroundColor DarkGray

    . (Join-Path $PSScriptRoot "kit.ps1")
    $kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev
    & (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Lua $Lua
    $failed = if ($LASTEXITCODE -ne 0) { 1 } else { 0 }

    # The Python tools (Tools/gen_no_disenchant.py #6, Tools/yield_report.py
    # #40), when Python is here (CI always runs them).
    $python = Get-Command python -ErrorAction SilentlyContinue
    Get-ChildItem (Join-Path $PSScriptRoot "test_*.py") | Sort-Object Name | ForEach-Object {
        if ($python) {
            Write-Host "-- $($_.Name) " -NoNewline -ForegroundColor Cyan
            $out = & $python.Source $_.FullName 2>&1
            Write-Host ($out | Select-Object -Last 1)
            if ($LASTEXITCODE -ne 0) { $out | Write-Host; $failed++ }
        } else {
            Write-Host "-- $($_.Name) skipped: no python on PATH" -ForegroundColor DarkGray
        }
    }

    if ($failed -gt 0) {
        Write-Host "Tests FAILED" -ForegroundColor Red
        exit 1
    }
    Write-Host "All tests passed." -ForegroundColor Green
}
finally {
    Pop-Location
}
