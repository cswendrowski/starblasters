$ErrorActionPreference = 'Stop'
$STANDALONE = 'C:\Users\Cody\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe'
$REPO = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $STANDALONE)) { throw "Standalone Godot not found at $STANDALONE" }

$capturesDir = Join-Path $REPO "captures"
if (-not (Test-Path $capturesDir)) { New-Item -ItemType Directory -Path $capturesDir | Out-Null }

# Delete stale frames so we can't mistake old files for success.
foreach ($n in @("near_planet", "two_away", "far", "belt")) {
    $p = Join-Path $capturesDir "star_system_$n.png"
    if (Test-Path $p) { Remove-Item $p -Force }
}

# Real GPU renderer (NOT --headless): PixelPlanets shaders + viewport texture
# come back black under headless.
Write-Output "Running star-system staging capture (near_planet, two_away, far, belt)..."
$output = & $STANDALONE --path $REPO res://scenes/dev/star_system_capture.tscn 2>&1
Write-Output $output

$ok = $true
foreach ($n in @("near_planet", "two_away", "far", "belt")) {
    $p = Join-Path $capturesDir "star_system_$n.png"
    if ((Test-Path $p) -and ((Get-Item $p).Length -gt 2048)) {
        Write-Output "SUCCESS: $p ($((Get-Item $p).Length) bytes)"
    } else {
        Write-Output "ERROR: missing/too-small $p"
        $ok = $false
    }
}

# Side-by-side montage (near_planet | two_away | far | belt) if ffmpeg is present.
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    $montage = Join-Path $capturesDir "star_system_montage.png"
    & ffmpeg -y `
        -i (Join-Path $capturesDir "star_system_near_planet.png") `
        -i (Join-Path $capturesDir "star_system_two_away.png") `
        -i (Join-Path $capturesDir "star_system_far.png") `
        -i (Join-Path $capturesDir "star_system_belt.png") `
        -filter_complex "[0:v][1:v][2:v][3:v]hstack=inputs=4" $montage | Out-Null
    if (Test-Path $montage) { Write-Output "Montage: $montage" }
}

if (-not $ok) { exit 1 }
