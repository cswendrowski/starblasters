param([double]$Fps = 2.0, [string]$OutName = "bullet_glow_styles")
$ErrorActionPreference = 'Continue'
# Godot 4.6.3 standalone. Must run WITHOUT --headless: the glow shader + WorldEnvironment
# bloom need a real GPU renderer (headless's dummy renderer returns null viewport textures).
$GODOT = 'E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64.exe'
$Repo = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Repo 'captures'
$FrameDir = Join-Path $OutDir 'bullet_glow_styles'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory $OutDir | Out-Null }
& $GODOT --path $Repo --script 'res://tools/capture_bullet_glow_styles.gd' | Out-Null
$Frames = Get-ChildItem "$FrameDir\*.png" -ErrorAction SilentlyContinue | Sort-Object Name
if (-not $Frames -or $Frames.Count -eq 0) { Write-Error "No frames captured to $FrameDir"; exit 1 }
$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')
$OutPath = Join-Path $OutDir "$OutName.gif"
$Pattern = Join-Path $FrameDir 'frame_%04d.png'
$LogPath = Join-Path $OutDir 'ffmpeg.log'
# Slideshow of distinct styles -> a global palette (stats_mode=full) avoids per-frame colour drift.
$FilterGraph = 'scale=960:-1:flags=neighbor,split[s0][s1];[s0]palettegen=stats_mode=full[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5'
$proc = Start-Process -FilePath 'ffmpeg' -ArgumentList @('-y','-framerate',$Fps,'-i',$Pattern,'-vf',$FilterGraph,$OutPath) -NoNewWindow -Wait -PassThru -RedirectStandardError $LogPath -RedirectStandardOutput "$LogPath.out"
if ($proc.ExitCode -ne 0) { Write-Error "ffmpeg exit $($proc.ExitCode). See $LogPath"; exit $proc.ExitCode }
Write-Output "Frames: $($Frames.Count)  ->  $OutPath"
