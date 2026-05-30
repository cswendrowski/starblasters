$ErrorActionPreference = 'Continue'  # Don't stop on non-terminating errors
$GODOT = 'C:\Users\Cody\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe'
$REPO = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $GODOT)) { throw "Godot not found at $GODOT" }

# Create captures directory if needed
$capturesDir = Join-Path $REPO "captures"
if (-not (Test-Path $capturesDir)) {
    New-Item -ItemType Directory -Path $capturesDir | Out-Null
}

# Delete stale frames directory
$framesDir = Join-Path $capturesDir "frames_light_patterns"
if (Test-Path $framesDir) {
    Remove-Item $framesDir -Recurse -Force
}

# Run the capture script
Write-Output "Running light patterns capture..."
& $GODOT --path $REPO -s tools/capture_light_patterns.gd 2>&1 | Out-Null

# Brief wait
Start-Sleep -Milliseconds 500

# Verify frames were created
if (-not (Test-Path $framesDir)) {
    Write-Output "ERROR: Frames directory not created"
    exit 1
}

$frameCount = (Get-ChildItem $framesDir -Filter "frame_*.png" | Measure-Object).Count
if ($frameCount -eq 0) {
    Write-Output "ERROR: No frames found"
    exit 1
}

Write-Output "SUCCESS: Created $frameCount frames"

# Convert frames to GIF using ffmpeg
Write-Output "Converting frames to GIF..."
$gifPath = Join-Path $capturesDir "light_patterns.gif"
$inputPattern = $framesDir + '/frame_%04d.png'
$palettePath = Join-Path $capturesDir "palette.png"

if (Test-Path $gifPath) {
    Remove-Item $gifPath -Force
}

# Palette pass
Write-Output "Generating palette..."
cmd /c "ffmpeg -y -framerate 20 -i $inputPattern -vf palettegen $palettePath" >$null 2>&1

if (-not (Test-Path $palettePath)) {
    Write-Output "ERROR: Failed to create palette"
    exit 1
}

# GIF pass
Write-Output "Creating GIF..."
cmd /c "ffmpeg -y -framerate 20 -i $inputPattern -i $palettePath -lavfi paletteuse $gifPath" >$null 2>&1

# Verify GIF
if (Test-Path $gifPath) {
    $gifSize = (Get-Item $gifPath).Length
    if ($gifSize -gt 2048) {
        Write-Output "SUCCESS: GIF created at $gifPath ($gifSize bytes)"
    } else {
        Write-Output "ERROR: GIF too small ($gifSize bytes)"
        exit 1
    }
} else {
    Write-Output "ERROR: GIF not created"
    exit 1
}

# Clean up
Write-Output "Cleaning up..."
Remove-Item $framesDir -Recurse -Force
Remove-Item $palettePath -Force -ErrorAction SilentlyContinue

Write-Output "Done!"
