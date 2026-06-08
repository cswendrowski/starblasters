#!/usr/bin/env pwsh
<#
    Capture Smart Bomb shockwave and generate GIF.
    Godot 4.6.3 standalone headless + ffmpeg.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Paths.
$GodotExe = "E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64.exe"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$CaptureScript = Join-Path $PSScriptRoot "capture_smart_bomb.gd"
$FramesDir = Join-Path $ProjectRoot "captures\smart_bomb"
$GifOutput = Join-Path $ProjectRoot "captures\smart_bomb.gif"

# Verify Godot binary exists.
if (-not (Test-Path $GodotExe)) {
    Write-Error "Godot not found at: $GodotExe"
    exit 1
}

# Clean up old frames.
if (Test-Path $FramesDir) {
    Remove-Item $FramesDir -Recurse -Force
}
New-Item $FramesDir -ItemType Directory -Force | Out-Null

# Run capture script. Must NOT use --headless; need real GPU for viewport texture grab.
Write-Host "[smart-bomb] Running Godot capture (windowed)..." -ForegroundColor Cyan
& $GodotExe --path $ProjectRoot --script $CaptureScript
if ($LASTEXITCODE -ne 0) {
    Write-Error "Godot capture failed with exit code $LASTEXITCODE"
    exit 1
}

# Count frames.
$FrameFiles = @(Get-ChildItem "$FramesDir\frame_*.png" -ErrorAction SilentlyContinue)
$FrameCount = $FrameFiles.Count
Write-Host "[smart-bomb] Captured $FrameCount frames" -ForegroundColor Green

if ($FrameCount -eq 0) {
    Write-Error "No frames captured; check the Godot output above."
    exit 1
}

# Generate GIF via ffmpeg (30 fps).
Write-Host "[smart-bomb] Generating GIF at 30 fps..." -ForegroundColor Cyan
$FramePattern = Join-Path $FramesDir "frame_%04d.png"
ffmpeg -y -framerate 30 -i $FramePattern -vf "fps=30" $GifOutput 2>&1 | Out-Null

if (-not (Test-Path $GifOutput)) {
    Write-Error "ffmpeg failed to generate GIF"
    exit 1
}

$GifSize = (Get-Item $GifOutput).Length / 1KB
Write-Host "[smart-bomb] GIF saved: $GifOutput ($([Math]::Round($GifSize, 1)) KB)" -ForegroundColor Green
Write-Host "[smart-bomb] Frames: $FramesDir" -ForegroundColor Green
