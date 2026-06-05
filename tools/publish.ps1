param(
  [Parameter(Mandatory=$true)][string]$Version
)
# Web export + butler push for Starblasters.
# Single-binary setup (2026-05-26 consolidation): editor + export both run
# the same standalone Godot 4.6.3. We dropped the 4.3 Mono editor since the
# project never used C#. If web export ever silently no-ops again, first
# check that this binary path still exists and matches the editor in use.
$ErrorActionPreference = 'Stop'
$STANDALONE_GODOT = 'E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64.exe'
$BUTLER = 'E:\tools\butler\butler.exe'
$REPO = Split-Path -Parent $PSScriptRoot
$OUT_DIR = Join-Path (Split-Path -Parent $REPO) 'Starblaster_html'
$OUT_HTML = Join-Path $OUT_DIR 'index.html'
$CHANNEL = 'tikibones/starblaster:html'

if (-not (Test-Path $STANDALONE_GODOT)) { throw "Standalone Godot not found at $STANDALONE_GODOT" }
if (-not (Test-Path $BUTLER)) { throw "butler not found at $BUTLER" }

# HARD GATE: every user-reachable scene must parse-clean on the same Godot
# version we're about to export with. With the single-binary consolidation
# this is now belt-and-braces (editor == exporter), but the audit still
# catches scripts that reference autoloads/classes only seeded by the
# editor's class cache.
Write-Output "Running parse_check across all user-reachable scenes..."
$checkScript = Join-Path $PSScriptRoot 'parse_check.ps1'
& $checkScript
if ($LASTEXITCODE -ne 0) { throw "parse_check failed - refusing to publish a build that won't run." }

# Update project.godot version
$proj = Join-Path $REPO 'project.godot'
(Get-Content $proj -Raw) -replace 'config/version="[^"]+"', "config/version=`"$Version`"" | Set-Content $proj -Encoding utf8

# Godot's exporter writes into OUT_DIR but does NOT create it — a missing dir
# makes the export a silent no-op (no index.pck). Ensure it exists (first publish
# on a fresh machine hits this).
if (-not (Test-Path $OUT_DIR)) { New-Item -ItemType Directory -Force $OUT_DIR | Out-Null }

# Capture mtime BEFORE export so we can detect a silent no-op.
$pckPath = Join-Path $OUT_DIR 'index.pck'
$mtimeBefore = if (Test-Path $pckPath) { (Get-Item $pckPath).LastWriteTimeUtc.Ticks } else { 0 }

Write-Output "Exporting Web (v$Version) ..."
# PowerShell 5.1 treats stderr from native exes as terminating errors under
# ErrorActionPreference=Stop. The Godot export writes harmless warnings (e.g.
# "Detected another project.godot at ...PixelPlanetsSource") to stderr, which
# would abort the publish even on a successful export. Swap policy locally to
# Continue and rely on the mtime check below to validate success.
$prevPref = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $STANDALONE_GODOT --path $REPO --headless --export-release "Web" $OUT_HTML 2>&1 | Out-Null
$ErrorActionPreference = $prevPref
# Godot exits non-zero on shutdown noise from editor plugins even on success.
# Do not check exit code - verify the output mtime advanced instead.

if (-not (Test-Path $pckPath)) { throw "Export produced no index.pck (preset failed silently)." }
$mtimeAfter = (Get-Item $pckPath).LastWriteTimeUtc.Ticks
if ($mtimeAfter -le $mtimeBefore) {
  throw "index.pck mtime did not advance (export was a no-op). Did the editor build mismatch the export target?"
}

Write-Output "Pushing to itch ..."
& $BUTLER push $OUT_DIR $CHANNEL --userversion $Version
if ($LASTEXITCODE -ne 0) { throw "butler push failed (exit $LASTEXITCODE)" }
Write-Output "Done: $Version live on $CHANNEL"
