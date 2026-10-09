<#
    deploy.ps1 - Deploy Shatter to the WoW: Forever AddOns folder.

    Usage:
        pwsh Tools/deploy.ps1
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\Games\WoW\_classic_beta_\Interface\AddOns"

    TOC-driven: the deployed folder gets Shatter.toc, LICENSE and exactly the
    files the TOC loads, each at its own relative path (Data\, Mail\, Modes\,
    UI\, Integrations\ are created as needed). A file the TOC names that is
    missing, or differs in case from the TOC line, fails the deploy before
    anything is copied - the client would load nothing for it, silently.

    Files are copied one by one, never whole directories onto same-named
    destination directories (that is how a nested UI\UI appears).

    The TBC addon lives in _anniversary_ under the same folder name. This script
    refuses that client: the Forever build there would overwrite the TBC one.
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

if ($AddOnsPath -match '_anniversary_') {
    throw "Refusing to deploy the Forever build into the TBC Anniversary client ($AddOnsPath)."
}
if (-not (Test-Path -LiteralPath $AddOnsPath)) {
    throw "AddOns path not found: $AddOnsPath"
}

$tocPath = Join-Path $RepoRoot "Shatter.toc"
$tocLines = Get-Content -LiteralPath $tocPath
if (-not ($tocLines | Where-Object { $_ -match '^##\s*Interface:\s*16001\s*$' })) {
    throw "Shatter.toc is not a Forever TOC (## Interface: 16001 missing)."
}

# Every non-blank, non-# line is a file the client loads, relative to the TOC.
$files = @()
foreach ($line in $tocLines) {
    $entry = $line.Trim()
    if ($entry -eq "" -or $entry.StartsWith("#")) { continue }
    $files += $entry
}

# Validate everything first: a half-copied addon is worse than none.
$missing = @()
foreach ($rel in $files) {
    $src = Join-Path $RepoRoot $rel
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { $missing += $rel; continue }
    # Windows paths are case-insensitive; the packaged zip and other clients
    # are not. Compare each segment against what is really on disk.
    $dir = $RepoRoot
    foreach ($segment in ($rel -split '\\')) {
        $actual = (Get-ChildItem -LiteralPath $dir -Force | Where-Object { $_.Name -ieq $segment } | Select-Object -First 1).Name
        if ($actual -cne $segment) { $missing += "$rel (case: on disk '$actual')"; break }
        $dir = Join-Path $dir $actual
    }
}
if ($missing.Count -gt 0) {
    throw "Shatter.toc names files that are missing or differ in case:`n  " + ($missing -join "`n  ")
}

$dest = Join-Path $AddOnsPath "Shatter"
Write-Host "Deploying Shatter (Forever) -> $dest" -ForegroundColor Cyan

foreach ($rel in @("Shatter.toc", "LICENSE") + $files) {
    $src = Join-Path $RepoRoot $rel
    $target = Join-Path $dest $rel
    $targetDir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $target -Force
}
Write-Host "  copied $($files.Count + 2) files" -ForegroundColor DarkGray

# Files an older deploy left behind that the TOC no longer loads are harmless to
# the client but misleading when diagnosing; name them rather than delete.
$expected = @{}
foreach ($rel in @("Shatter.toc", "LICENSE") + $files) { $expected[$rel.ToLowerInvariant()] = $true }
foreach ($item in Get-ChildItem -LiteralPath $dest -Recurse -File) {
    $rel = $item.FullName.Substring($dest.Length + 1)
    if (-not $expected.ContainsKey($rel.ToLowerInvariant())) {
        Write-Host "  note: $rel is in the deployed folder but not in the TOC" -ForegroundColor DarkYellow
    }
}

# The packager substitutes @project-version@ at release time. Substitute in the
# DEPLOYED copy only; editing the repo copy is how a literal version gets
# committed over the token.
$rev = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
    try { $rev = (git -C $RepoRoot rev-parse --short HEAD 2>$null) } catch { $rev = $null }
}
$label = if ($rev) { "dev-$rev" } else { "dev" }
$deployedToc = Join-Path $dest "Shatter.toc"
(Get-Content -LiteralPath $deployedToc -Raw).Replace('@project-version@', $label) |
    Set-Content -LiteralPath $deployedToc -NoNewline
Write-Host "  version -> $label (deployed copy only)" -ForegroundColor DarkGray

Write-Host "Done." -ForegroundColor Green
Write-Host ""
Write-Host "In-game:" -ForegroundColor Yellow
Write-Host "  /console scriptErrors 1   (errors are OFF by default on this client)"
Write-Host "  /reload                   (a brand-new addon folder needs a full client restart once)"
Write-Host "  /shatter"
