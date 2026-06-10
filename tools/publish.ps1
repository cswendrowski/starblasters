param(
  [Parameter(Mandatory=$true)][string]$Version
)
# WINDOWS export + butler push for Starblaster (renderer pivot 2026-06-10: Forward+ renderer,
# Windows-only distribution — the old Web/html pipeline is retired; the Web preset remains in
# export_presets.cfg but is no longer published).
# Single-binary setup (2026-05-26 consolidation): editor + export both run the same standalone
# Godot 4.6.3. If the export ever silently no-ops, first check this binary path still exists and
# matches the editor in use.
$ErrorActionPreference = 'Stop'
$STANDALONE_GODOT = 'E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64.exe'
$BUTLER = 'E:\tools\butler\butler.exe'
$REPO = Split-Path -Parent $PSScriptRoot
$OUT_DIR = Join-Path (Split-Path -Parent $REPO) 'Starblaster_win'
$OUT_EXE = Join-Path $OUT_DIR 'Starblaster.exe'
$CHANNEL = 'tikibones/starblaster:windows'

if (-not (Test-Path $STANDALONE_GODOT)) { throw "Standalone Godot not found at $STANDALONE_GODOT" }
if (-not (Test-Path $BUTLER)) { throw "butler not found at $BUTLER" }

# HARD GATE: every user-reachable scene must parse-clean (plus the fail-closed all-scripts compile
# stage) on the same Godot version we're about to export with.
Write-Output "Running parse_check across all user-reachable scenes..."
$checkScript = Join-Path $PSScriptRoot 'parse_check.ps1'
& $checkScript
if ($LASTEXITCODE -ne 0) { throw "parse_check failed - refusing to publish a build that won't run." }

# Update project.godot version.
# Write UTF-8 WITHOUT a BOM. PowerShell 5.1's `Set-Content -Encoding utf8` prepends a BOM
# (EF BB BF); Godot then round-trips it into mojibake keys. Use .NET to write BOM-less UTF-8.
$proj = Join-Path $REPO 'project.godot'
$projText = (Get-Content $proj -Raw) -replace 'config/version="[^"]+"', "config/version=`"$Version`""
[System.IO.File]::WriteAllText($proj, $projText, (New-Object System.Text.UTF8Encoding $false))

# Godot's exporter writes into OUT_DIR but does NOT create it — a missing dir makes the export a
# silent no-op. Ensure it exists.
if (-not (Test-Path $OUT_DIR)) { New-Item -ItemType Directory -Force $OUT_DIR | Out-Null }

# Capture mtime BEFORE export so we can detect a silent no-op. The preset embeds the pck in the
# exe (binary_format/embed_pck=true), so the exe IS the build artifact.
$mtimeBefore = if (Test-Path $OUT_EXE) { (Get-Item $OUT_EXE).LastWriteTimeUtc.Ticks } else { 0 }

Write-Output "Exporting Windows (v$Version, Forward+) ..."
# PowerShell 5.1 treats stderr from native exes as terminating errors under
# ErrorActionPreference=Stop; the Godot export writes harmless warnings to stderr. Swap policy
# locally to Continue and rely on the mtime check below to validate success.
$prevPref = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $STANDALONE_GODOT --path $REPO --headless --export-release "Starblaster" $OUT_EXE 2>&1 | Out-Null
$ErrorActionPreference = $prevPref
# Godot exits non-zero on shutdown noise even on success — verify the artifact instead.

if (-not (Test-Path $OUT_EXE)) { throw "Export produced no Starblaster.exe (preset failed silently)." }
$mtimeAfter = (Get-Item $OUT_EXE).LastWriteTimeUtc.Ticks
if ($mtimeAfter -le $mtimeBefore) {
  throw "Starblaster.exe mtime did not advance (export was a no-op). Check export templates for 4.6.3."
}

Write-Output "Pushing to itch ..."
& $BUTLER push $OUT_DIR $CHANNEL --userversion $Version
if ($LASTEXITCODE -ne 0) { throw "butler push failed (exit $LASTEXITCODE)" }
Write-Output "Done: $Version live on $CHANNEL"
