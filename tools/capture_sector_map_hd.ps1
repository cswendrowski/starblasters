param([string]$OutName = "sector_map_hd")
$ErrorActionPreference = 'Continue'
$GODOT = 'C:\Users\Cody\Downloads\Godot_v4.3-stable_mono_win64\Godot_v4.3-stable_mono_win64\Godot.exe'
$Repo = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Repo 'captures'
$FrameDir = Join-Path $OutDir 'sector_map_hd'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory $OutDir | Out-Null }
& $GODOT --path $Repo -s 'res://tools/capture_sector_map_hd.gd' | Out-Null
$Frames = Get-ChildItem "$FrameDir\*.png" -ErrorAction SilentlyContinue | Sort-Object Name
if (-not $Frames -or $Frames.Count -eq 0) { Write-Error "No frames captured to $FrameDir"; exit 1 }
Write-Output (Join-Path $FrameDir 'frame_0000.png')
