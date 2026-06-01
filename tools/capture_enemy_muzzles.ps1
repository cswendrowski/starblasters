$ErrorActionPreference = 'Continue'
$GODOT = 'C:\Users\Cody\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe'
$REPO = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $GODOT)) { throw "Godot not found at $GODOT" }

$capturesDir = Join-Path $REPO "captures"
if (-not (Test-Path $capturesDir)) {
    New-Item -ItemType Directory -Path $capturesDir | Out-Null
}

$framesDir = Join-Path $capturesDir "frames_enemy_muzzles"
if (Test-Path $framesDir) {
    Remove-Item $framesDir -Recurse -Force
}

Write-Output "Running enemy muzzles capture..."
& $GODOT --path $REPO -s tools/capture_enemy_muzzles.gd 2>&1 | Out-Null

Start-Sleep -Milliseconds 500

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

Write-Output "Converting frames to GIF..."
$gifPath = Join-Path $capturesDir "enemy_muzzles.gif"
$inputPattern = $framesDir + '/frame_%04d.png'
$palettePath = Join-Path $capturesDir "palette_enemy_muzzles.png"

if (Test-Path $gifPath) { Remove-Item $gifPath -Force }

Write-Output "Generating palette..."
cmd /c "ffmpeg -y -framerate 20 -i $inputPattern -vf palettegen $palettePath" >$null 2>&1
if (-not (Test-Path $palettePath)) {
    Write-Output "ERROR: Failed to create palette"
    exit 1
}

Write-Output "Creating GIF..."
cmd /c "ffmpeg -y -framerate 20 -i $inputPattern -i $palettePath -lavfi paletteuse $gifPath" >$null 2>&1

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

Write-Output "Cleaning up..."
Remove-Item $framesDir -Recurse -Force
Remove-Item $palettePath -Force -ErrorAction SilentlyContinue

Write-Output "Done!"
