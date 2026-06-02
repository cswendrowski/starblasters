$ErrorActionPreference = 'Continue'
$GODOT = 'E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64.exe'
$REPO = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $GODOT)) { throw "Godot not found at $GODOT" }

$capturesDir = Join-Path $REPO "captures"
if (-not (Test-Path $capturesDir)) {
    New-Item -ItemType Directory -Path $capturesDir | Out-Null
}

$framesDir = Join-Path $capturesDir "frames_missile_cruiser"
if (Test-Path $framesDir) {
    Remove-Item $framesDir -Recurse -Force
}

# Run the capture script (REAL GPU — no --headless so _draw / shaders render).
# Godot's -s script runner can return before the async _capture_loop finishes
# writing all frames, so wait for the process AND poll until the frame count
# stops growing before converting.
Write-Output "Running missile cruiser capture..."
$proc = Start-Process -FilePath $GODOT -ArgumentList @('--path', $REPO, '-s', 'tools/capture_missile_cruiser.gd') -PassThru -NoNewWindow
$proc.WaitForExit()

# Poll until the frame count is stable (covers any lingering async writes).
$lastCount = -1
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 400
    if (-not (Test-Path $framesDir)) { continue }
    $c = (Get-ChildItem $framesDir -Filter "frame_*.png" | Measure-Object).Count
    if ($c -eq $lastCount -and $c -gt 0) { break }
    $lastCount = $c
}

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
$gifPath = Join-Path $capturesDir "missile_cruiser.gif"
$inputPattern = $framesDir + '/frame_%04d.png'
$palettePath = Join-Path $capturesDir "palette_mc.png"

if (Test-Path $gifPath) { Remove-Item $gifPath -Force }

# Downscale to keep the GIF Discord-friendly (full 1920x1080 @ 16s produced a
# ~110MB file). Half-res (960 wide) + 16fps + bayer dithering keeps it readable
# while landing well under the size cap.
$scaleFilter = "fps=10,scale=600:-1:flags=lanczos"
cmd /c "ffmpeg -y -framerate 20 -i $inputPattern -vf `"$scaleFilter,palettegen`" $palettePath" >$null 2>&1
if (-not (Test-Path $palettePath)) {
    Write-Output "ERROR: Failed to create palette"
    exit 1
}
cmd /c "ffmpeg -y -framerate 20 -i $inputPattern -i $palettePath -lavfi `"$scaleFilter [x]; [x][1:v] paletteuse=dither=bayer`" $gifPath" >$null 2>&1

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
