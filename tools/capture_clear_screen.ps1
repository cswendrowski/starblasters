param(
  [int]$Fps = 30,
  [string]$OutName = "clear_screen"
)
$ErrorActionPreference = 'Continue'
$GODOT = 'E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe'
$Repo = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Repo 'captures'
$FrameDir = Join-Path $OutDir 'clear_screen'

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory $OutDir | Out-Null }

# Real GPU renderer (NOT --headless): SubViewport texture grab + HDR bloom
# require a real frame buffer. Headless uses dummy renderer → null textures.
& $GODOT --path $Repo -s 'res://tools/capture_clear_screen.gd' 2>&1

$Frames = Get-ChildItem "$FrameDir\*.png" -ErrorAction SilentlyContinue | Sort-Object Name
if (-not $Frames -or $Frames.Count -eq 0) { Write-Error "No frames captured to $FrameDir"; exit 1 }

$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')

$OutPath = Join-Path $OutDir "$OutName.gif"
$Pattern = Join-Path $FrameDir 'frame_%04d.png'
$LogPath = Join-Path $OutDir 'ffmpeg.log'
# Source is the 1920x1080 window (canvas_items stretch already upscaled the
# 480-authored content 4×). Downscale to 1440x810 with lanczos, then palettize.
$FilterGraph = 'scale=960:540:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5'
$proc = Start-Process -FilePath 'ffmpeg' -ArgumentList @('-y','-framerate',$Fps,'-i',$Pattern,'-vf',$FilterGraph,$OutPath) -NoNewWindow -Wait -PassThru -RedirectStandardError $LogPath -RedirectStandardOutput "$LogPath.out"
if ($proc.ExitCode -ne 0) { Write-Error "ffmpeg exit $($proc.ExitCode). See $LogPath"; exit $proc.ExitCode }

Write-Output $OutPath
