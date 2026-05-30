$ErrorActionPreference = 'Stop'
$STANDALONE = 'C:\Users\Cody\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe'
$REPO = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $STANDALONE)) { throw "Standalone Godot not found at $STANDALONE" }

# Create captures directory if needed
$capturesDir = Join-Path $REPO "captures"
if (-not (Test-Path $capturesDir)) {
    New-Item -ItemType Directory -Path $capturesDir | Out-Null
}

# Delete stale PNG so we can't mistake an old file for success
$png_path = Join-Path $capturesDir "hud_live.png"
if (Test-Path $png_path) {
    Remove-Item $png_path -Force
    Write-Output "Removed stale PNG"
}

# Run the scene directly (no -s trampoline; scene handles save+quit)
Write-Output "Running live HUD capture..."
$output = & $STANDALONE --path $REPO res://scenes/dev/hud_live_capture.tscn 2>&1
Write-Output $output

# Verify the PNG was freshly written and is > 2KB
if (Test-Path $png_path) {
    $size = (Get-Item $png_path).Length
    if ($size -gt 2048) {
        Write-Output "SUCCESS: Screenshot created ($size bytes)"
        Write-Output $png_path
    } else {
        Write-Output "ERROR: Screenshot too small ($size bytes) - likely a black frame"
        exit 1
    }
} else {
    Write-Output "ERROR: Screenshot not found at $png_path"
    exit 1
}
