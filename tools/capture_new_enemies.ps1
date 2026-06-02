param([int]$Fps = 30, [string[]]$Clips)
$ErrorActionPreference = 'Continue'
$GODOT = 'E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64.exe'
$Repo = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Repo 'captures\new_enemies'

$AllClips = @('frigate_side','frigate_top','bomber_wing','minelayer','beamer_down','beamer_track')
if (-not $Clips -or $Clips.Count -eq 0) { $Clips = $AllClips }

# Render the clips (no --headless; the viewport grab needs a real frame). Pass
# the requested clip names as user args after `--` so only those are rendered.
& $GODOT --path $Repo -s 'res://tools/capture_new_enemies.gd' -- @Clips | Out-Null

# Refresh PATH so ffmpeg resolves without a shell restart.
$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')
$FilterGraph = 'scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5'
foreach ($c in $Clips) {
  $FrameDir = Join-Path $OutDir $c
  $Frames = Get-ChildItem "$FrameDir\*.png" -ErrorAction SilentlyContinue | Sort-Object Name
  if (-not $Frames -or $Frames.Count -eq 0) { Write-Warning "No frames for $c"; continue }
  $OutPath = Join-Path $OutDir "$c.gif"
  $Pattern = Join-Path $FrameDir 'frame_%04d.png'
  $LogPath = Join-Path $OutDir "ffmpeg_$c.log"
  $proc = Start-Process -FilePath 'ffmpeg' -ArgumentList @('-y','-framerate',$Fps,'-i',$Pattern,'-vf',$FilterGraph,$OutPath) -NoNewWindow -Wait -PassThru -RedirectStandardError $LogPath -RedirectStandardOutput "$LogPath.out"
  if ($proc.ExitCode -ne 0) { Write-Warning "ffmpeg exit $($proc.ExitCode) for $c. See $LogPath" }
  else { Write-Output $OutPath }
}
