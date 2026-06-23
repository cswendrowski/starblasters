# repro_draw_index_crash.ps1 — windowed, real-renderer repro of the
#   ERROR: Parameter "canvas_item" is null  at canvas_item_set_draw_index
#   (servers/rendering/renderer_canvas_cull.cpp:1917)  → SIGSEGV
# crash (2026-06-22 review, finding #1).
#
# Boots scenes/dev/draw_index_crash_lab.tscn, which keeps a dense crowd of real
# engine-trail enemies alive at a shared root and kills them (single + mass wipes)
# over and over, with the asteroid-field backdrop populated. The hypothesis is that
# the absolute-z trail/dust/debris CanvasItems freeing on the death frame trip the
# draw-order reindex over a freed RID.
#
# HEADLESS CANNOT FAULT (the dummy renderer skips the canvas path), so this launches
# the _console binary WINDOWED on the project-default Forward+/Vulkan renderer.
#
#   tools\repro_draw_index_crash.ps1               # default crowd (30)
#   tools\repro_draw_index_crash.ps1 -Crowd 50     # denser canvas → more likely to race
#
# Esc in the game window quits cleanly. If it crashes, send the .err log + the
# in-game log: %APPDATA%\Godot\app_userdata\<project>\draw_index_crash.log

param([int]$Crowd = 0)

$Bin  = 'E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe'   # _console = reliable stdout
$Repo = Split-Path -Parent $PSScriptRoot
$Scene = 'res://scenes/dev/draw_index_crash_lab.tscn'
if (-not (Test-Path $Bin)) { throw "Godot console binary not found at $Bin" }

$stamp = Get-Date -Format "MMdd_HHmmss"
$out = Join-Path $env:USERPROFILE "Desktop\sb_drawidx_${stamp}.out.txt"
$err = Join-Path $env:USERPROFILE "Desktop\sb_drawidx_${stamp}.err.txt"

$argList = @("--path", $Repo, $Scene, "--verbose", "--accurate-breadcrumbs")
if ($Crowd -gt 0) { $argList += @("++", "--crowd", "$Crowd") }

Write-Host "Launching draw-index crash repro  [Forward+/Vulkan, WINDOWED]" -ForegroundColor Cyan
if ($Crowd -gt 0) { Write-Host "  crowd override: $Crowd" }
Write-Host "  out: $out"
Write-Host "  err: $err"
Write-Host "  in-game log: %APPDATA%\Godot\app_userdata\<project>\draw_index_crash.log"
Write-Host "  Let it run; Esc in the window quits cleanly.`n"

$p = Start-Process -FilePath $Bin -ArgumentList $argList `
        -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait -PassThru

Write-Host "`n--- Godot exited (code $($p.ExitCode)) ---" -ForegroundColor Yellow
Write-Host "`n=== last 40 lines of stderr (crash backtrace lands here) ===" -ForegroundColor Yellow
if (Test-Path $err) { Get-Content $err -Tail 40 }

$pat = 'canvas_item|renderer_canvas_cull|set_draw_index|signal 11|CrashHandlerException|SCRIPT ERROR'
Write-Host "`n=== draw-index / crash markers across both logs ===" -ForegroundColor Yellow
$hits = Select-String -Path $out,$err -Pattern $pat -ErrorAction SilentlyContinue
if ($hits) { $hits | Select-Object -ExpandProperty Line -Unique | Select-Object -Last 40 }
else { Write-Host "(none found — if it died without these, send the full .err log)" }

if ($p.ExitCode -ne 0) {
  Write-Host "`nNon-zero exit + a canvas_item null flood above => finding #1 CONFIRMED." -ForegroundColor Green
} else {
  Write-Host "`nClean exit. Re-run with a larger -Crowd, or it survived (finding #1 not reproduced this run)." -ForegroundColor Green
}
