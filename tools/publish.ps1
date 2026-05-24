param(
  [Parameter(Mandatory=$true)][string]$Version
)
# Web export + butler push for Starblasters.
# IMPORTANT: Godot 4 with C#/.NET (Mono) CANNOT export to Web - it fails
# silently with a stderr error and exit code 5. We must use the NON-Mono
# standalone Godot 4.4.1 build for the web target. Mono build stays for
# day-to-day editor work (it's what the project was authored against).
# If a future export ever silently no-ops again, check this script first.
$ErrorActionPreference = 'Stop'
$STANDALONE_GODOT = 'C:\Users\Cody\Downloads\PortalSDK(3)\Godot_v4.4.1-stable_win64.exe'
$BUTLER = 'C:\Users\Cody\Downloads\butler-windows-amd64\windows-amd64\butler.exe'
$REPO = Split-Path -Parent $PSScriptRoot
$OUT_DIR = Join-Path (Split-Path -Parent $REPO) 'Starblasters_html'
$OUT_HTML = Join-Path $OUT_DIR 'index.html'
$CHANNEL = 'cswendrowski/starblaster:html'

if (-not (Test-Path $STANDALONE_GODOT)) { throw "Standalone Godot not found at $STANDALONE_GODOT" }
if (-not (Test-Path $BUTLER)) { throw "butler not found at $BUTLER" }

# HARD GATE: every user-reachable scene must parse-clean on the same Godot
# version we're about to export with. 4.3 editor accepts walrus inference
# on untyped Arrays and duplicate `var` shadows; 4.4.1 rejects both —
# silent in headless tests, fatal in browser. Run the project-wide
# parser audit before touching the export pipeline.
Write-Output "Running parse_check across all user-reachable scenes..."
$checkScript = Join-Path $PSScriptRoot 'parse_check.ps1'
& $checkScript
if ($LASTEXITCODE -ne 0) { throw "parse_check failed - refusing to publish a build that won't run." }

# Update project.godot version
$proj = Join-Path $REPO 'project.godot'
(Get-Content $proj -Raw) -replace 'config/version="[^"]+"', "config/version=`"$Version`"" | Set-Content $proj -Encoding utf8

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
