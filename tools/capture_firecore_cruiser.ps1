param([int]$Fps = 12, [string]$OutName = "firecore_cruiser")
$ErrorActionPreference = 'Continue'
$GODOT = 'C:\Users\Cody\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe'
$Repo = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Repo 'captures'
$FrameDir = Join-Path $OutDir 'firecore_cruiser'

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory $OutDir | Out-Null }

Write-Output "[firecore] Capturing frames..."
& $GODOT --path $Repo -s 'res://tools/capture_firecore_cruiser.gd' 2>&1 | Out-Null

$Frames = Get-ChildItem "$FrameDir\*.png" -ErrorAction SilentlyContinue | Sort-Object Name
if (-not $Frames -or $Frames.Count -eq 0) { 
  Write-Error "No frames captured to $FrameDir"
  exit 1
}

Write-Output "[firecore] Building palette..."
$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')
$Pattern = Join-Path $FrameDir 'frame_%04d.png'
$LogPath = Join-Path $OutDir 'ffmpeg_firecore.log'
$OutPath = Join-Path $OutDir "$OutName.gif"

& ffmpeg -y -framerate $Fps -i "$Pattern" -vf palettegen "$($OutDir)\palette_firecore.png" 2>&1 | Out-File $LogPath

Write-Output "[firecore] Building GIF..."
& ffmpeg -y -framerate $Fps -i "$Pattern" -i "$($OutDir)\palette_firecore.png" -lavfi paletteuse "$OutPath" 2>&1 | Out-File $LogPath -Append

$GIF_SIZE = (Get-Item $OutPath).Length
Write-Output "[firecore] GIF complete: $OutPath ($GIF_SIZE bytes)"

if ($GIF_SIZE -lt 2048) {
  Write-Error "GIF is too small ($GIF_SIZE bytes) - likely a render error"
  exit 1
}

Write-Output $OutPath
