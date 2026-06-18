# run_renderer.ps1 — launch Starblaster on a chosen renderer with a captured verbose crash log, to
# diagnose the intermittent Forward+/Vulkan signal-11 crash (Roman 2026-06-17). Play until it crashes
# (or quit normally); on exit it prints the Vulkan/crash markers + where the full logs are.
#
#   tools\run_renderer.ps1            # vulkan  — current Forward+/Vulkan (default). Use to CAPTURE a crash.
#   tools\run_renderer.ps1 -Mode d3d12   # Forward+ but on the D3D12 driver (keeps all visuals, swaps Vulkan→DX12).
#                                        #   If crashes STOP here → it's the Vulkan DRIVER (update NVIDIA drivers).
#   tools\run_renderer.ps1 -Mode compat  # Compatibility (OpenGL) renderer (drops hdr_2d glow etc.).
#                                        #   If crashes STOP here too → it's the Forward+/Vulkan path in general.
#
# Decision tree: vulkan crashes + d3d12 stable  => Vulkan driver bug (drivers/Steam-overlay).
#                vulkan+d3d12 crash, compat stable => Forward+ render path (engine/Godot version).
#                all three crash => not renderer-specific; symbolicate (Calinou/godot-debug-builds).

param([ValidateSet("vulkan","d3d12","compat")][string]$Mode = "vulkan")

$Bin  = 'E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe'   # _console = reliable stdout
$Repo = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $Bin)) { throw "Godot console binary not found at $Bin" }

$stamp = Get-Date -Format "MMdd_HHmmss"
$out = Join-Path $env:USERPROFILE "Desktop\sb_${Mode}_${stamp}.out.txt"
$err = Join-Path $env:USERPROFILE "Desktop\sb_${Mode}_${stamp}.err.txt"

$argList = @("--path", $Repo, "--verbose", "--accurate-breadcrumbs")
switch ($Mode) {
    "d3d12"  { $argList += @("--rendering-driver", "d3d12") }
    "compat" { $argList += @("--rendering-method", "gl_compatibility") }
    default  { }   # vulkan / forward_plus = project default, no override
}

Write-Host "Launching Starblaster  [renderer: $Mode]" -ForegroundColor Cyan
Write-Host "Play until it crashes (or quit the game normally). Logs:" -ForegroundColor Cyan
Write-Host "  out: $out"
Write-Host "  err: $err`n"

$p = Start-Process -FilePath $Bin -ArgumentList $argList `
        -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait -PassThru

Write-Host "`n--- Godot exited (code $($p.ExitCode)) ---" -ForegroundColor Yellow
Write-Host "`n=== last 30 lines of stderr (crash backtrace lands here) ===" -ForegroundColor Yellow
if (Test-Path $err) { Get-Content $err -Tail 30 }

Write-Host "`n=== Vulkan / crash markers across both logs ===" -ForegroundColor Yellow
$pat = "vkCreateGraphicsPipelines|device was lost|VK_ERROR_DEVICE_LOST|fence_wait|Fossilize|signal 11|CrashHandlerException|SCRIPT ERROR|Vulkan device"
$hits = Select-String -Path $out,$err -Pattern $pat -ErrorAction SilentlyContinue
if ($hits) { $hits | Select-Object -ExpandProperty Line -Unique | Select-Object -Last 30 }
else { Write-Host "(none found — if it crashed without these, send me the full .err log)" }

Write-Host "`nFull logs saved on your Desktop. Send me the .err file if it crashed." -ForegroundColor Green
