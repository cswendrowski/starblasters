param([int]$Fps = 24)
$ErrorActionPreference = 'Continue'
$GODOT = 'C:\Users\Cody\Downloads\Godot_v4.3-stable_mono_win64\Godot_v4.3-stable_mono_win64\Godot.exe'
$Repo = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Repo 'captures'
$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')
$FilterGraph = 'scale=480:-1:flags=neighbor,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5'

foreach ($variant in @('a','b')) {
  $script = "res://tools/capture_shadow_$variant.gd"
  $FrameDir = Join-Path $OutDir "shadow_$variant"
  & $GODOT --path $Repo -s $script | Out-Null
  $Frames = Get-ChildItem "$FrameDir\*.png" -ErrorAction SilentlyContinue
  if (-not $Frames -or $Frames.Count -eq 0) { Write-Error "No frames for $variant"; continue }
  $OutPath = Join-Path $OutDir "shadow_$variant.gif"
  $Pattern = Join-Path $FrameDir 'frame_%04d.png'
  Start-Process -FilePath 'ffmpeg' -ArgumentList @('-y','-framerate',$Fps,'-i',$Pattern,'-vf',$FilterGraph,$OutPath) -NoNewWindow -Wait | Out-Null
  Write-Output $OutPath
}
