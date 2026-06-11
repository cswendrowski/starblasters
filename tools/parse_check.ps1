$ErrorActionPreference = 'Stop'
$STANDALONE = 'E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64.exe'
$REPO = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $STANDALONE)) { throw "Standalone Godot not found at $STANDALONE" }

# Scenes that are user-reachable and route through their own scripts. If
# ANY of these fails to parse under the editor+export Godot, the build
# that gets published will hit the same error in the browser. Pre-publish gate.
$scenes = @(
  'res://scenes/main.tscn',
  'res://scenes/main_menu.tscn',
  'res://scenes/dev_menu.tscn',
  'res://scenes/dev/enemy_bench.tscn',
  'res://scenes/dev/lane_visualizer.tscn',
  'res://scenes/dev/pattern_eligibility_editor.tscn',
  'res://scenes/dev/movement_test.tscn',
  'res://scenes/dev/parallax_tuner.tscn',
  'res://scenes/dev/ui_designer.tscn',
  'res://scenes/dev/asteroid_lab.tscn',
  'res://scenes/dev/shader_lab.tscn',
  'res://scenes/dev/weapon_lab.tscn',
  'res://scenes/sector_map_hd.tscn',
  'res://scenes/outpost.tscn',
  'res://scenes/manage_ship.tscn',
  'res://scenes/signal_event.tscn',
  'res://scenes/cleared_summary.tscn',
  'res://scenes/run_summary.tscn',
  'res://scenes/hangar.tscn'
)

$failed = @()
foreach ($scene in $scenes) {
  $out = & $STANDALONE --path $REPO --headless $scene --quit-after 2 2>&1
  $errors = $out | Select-String -Pattern 'SCRIPT ERROR|Parse Error|Failed to load script' | Select-Object -First 3
  if ($errors) {
    $failed += @{ scene = $scene; errors = $errors }
  } else {
    Write-Output "OK $scene"
  }
}

if ($failed.Count -gt 0) {
  Write-Output "------"
  Write-Output "PARSE CHECK FAILED on $($failed.Count) scene(s):"
  foreach ($f in $failed) {
    Write-Output "  $($f.scene):"
    foreach ($e in $f.errors) { Write-Output "    $e" }
  }
  exit 1
}

# Booting the scenes above only parses scripts reachable AT LOAD TIME. Scripts that
# are instantiated dynamically at RUNTIME (enemy_core via wave.enemy_scene.instantiate(),
# bosses, projectiles, effects) are NOT covered, so a parse error there ships silently
# (2026-06-04: enemy_core const bug -> zero enemies, yet parse_check passed). Compile
# EVERY .gd so runtime-only scripts are gated too.
Write-Output "------"
Write-Output "Compiling all .gd scripts (runtime-only coverage)..."
# Gate on a RESULT FILE, fail-closed (2026-06-10): the win64 GUI-subsystem exe drops console
# output non-deterministically under redirection, so the old grep-the-output gate silently
# PASSED a hard parse error (the frozen-firecore bug shipped through a green gate).
# compile_check.gd writes tools/_compile_check_result.txt with an explicit VERDICT; a missing
# file means the check never ran = FAIL.
$resultFile = Join-Path $REPO 'tools\_compile_check_result.txt'
if (Test-Path $resultFile) { Remove-Item $resultFile -Force }
# NO stderr redirection here: under $ErrorActionPreference='Stop', PS 5.1 wraps a native exe's
# stderr lines (even benign Godot WARNINGs) into terminating ErrorRecords when 2>&1 is piped,
# killing this script mid-gate. The verdict comes from the result FILE, not the output.
& $STANDALONE --path $REPO --headless -s res://tools/compile_check.gd | Out-Null
if (-not (Test-Path $resultFile)) {
  Write-Output "SCRIPT COMPILE CHECK FAILED - compile_check.gd produced no result file (did not run)."
  exit 1
}
$resultLines = Get-Content $resultFile
$verdict = $resultLines | Select-String -Pattern '^VERDICT: PASS'
if (-not $verdict) {
  Write-Output "SCRIPT COMPILE CHECK FAILED - a .gd has a parse error:"
  foreach ($e in ($resultLines | Select-Object -First 8)) { Write-Output "    $e" }
  exit 1
}
Write-Output ($resultLines | Select-Object -First 1)

Write-Output "------"
Write-Output "All scenes parse-clean."
exit 0
