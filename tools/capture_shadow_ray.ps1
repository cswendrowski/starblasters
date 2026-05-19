param([int]$Fps = 24, [string]$OutName = "shadow_ray")
$ErrorActionPreference = 'Continue'
$GODOT = 'C:\Users\Cody\Downloads\Godot_v4.3-stable_mono_win64\Godot_v4.3-stable_mono_win64\Godot.exe'
$Repo = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Repo 'captures'
$FrameDir = Join-Path $OutDir 'shadow_ray'
& $GODOT --path $Repo -s 'res://tools/capture_shadow_ray.gd' | Out-Null
$Frames = Get-ChildItem "$FrameDir\*.png" -ErrorAction SilentlyContinue | Sort-Object Name
if (-not $Frames -or $Frames.Count -eq 0) { Write-Error "No frames"; exit 1 }
$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')
$OutPath = Join-Path $OutDir "$OutName.gif"
$Pattern = Join-Path $FrameDir 'frame_%04d.png'
$FilterGraph = 'scale=480:-1:flags=neighbor,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5'
Start-Process -FilePath 'ffmpeg' -ArgumentList @('-y','-framerate',$Fps,'-i',$Pattern,'-vf',$FilterGraph,$OutPath) -NoNewWindow -Wait | Out-Null
Write-Output $OutPath
