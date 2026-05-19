param(
  [int]$Demo = 0,
  [float]$Duration = 3.0,
  [int]$Fps = 30,
  [switch]$Gif,
  [string]$OutName = "capture"
)
$ErrorActionPreference = 'Continue'
$GODOT = 'C:\Users\Cody\Downloads\Godot_v4.3-stable_mono_win64\Godot_v4.3-stable_mono_win64\Godot.exe'
$Repo = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Repo 'captures'
$FrameDir = Join-Path $OutDir 'frames'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory $OutDir | Out-Null }
if (Test-Path $FrameDir) { Remove-Item "$FrameDir\*.png" -Force -ErrorAction SilentlyContinue }
else { New-Item -ItemType Directory $FrameDir | Out-Null }

$Scene = 'res://scenes/dev/feature_showcase.tscn'
$Args = @(
  '--path', $Repo,
  $Scene,
  "--capture-demo=$Demo",
  "--capture-duration=$Duration",
  "--capture-fps=$Fps",
  "--capture-dir=$FrameDir",
  '--quit-after-capture'
)
& $GODOT @Args | Out-Null

$Frames = Get-ChildItem "$FrameDir\*.png" -ErrorAction SilentlyContinue | Sort-Object Name
if (-not $Frames -or $Frames.Count -eq 0) { Write-Error "No frames captured to $FrameDir"; exit 1 }

# Refresh PATH so ffmpeg is visible without a shell restart
$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')

if ($Gif) {
  $OutPath = Join-Path $OutDir "$OutName.gif"
  $Pattern = Join-Path $FrameDir 'frame_%04d.png'
  $LogPath = Join-Path $OutDir 'ffmpeg.log'
  $FilterGraph = 'scale=540:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5'
  $proc = Start-Process -FilePath 'ffmpeg' -ArgumentList @('-y','-framerate',$Fps,'-i',$Pattern,'-vf',$FilterGraph,$OutPath) -NoNewWindow -Wait -PassThru -RedirectStandardError $LogPath -RedirectStandardOutput "$LogPath.out"
  if ($proc.ExitCode -ne 0) { Write-Error "ffmpeg exit $($proc.ExitCode). See $LogPath"; exit $proc.ExitCode }
} else {
  $OutPath = Join-Path $OutDir "$OutName.png"
  Copy-Item $Frames[-1].FullName $OutPath -Force
}
Write-Output $OutPath
