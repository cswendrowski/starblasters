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
  'res://scenes/dev/shipyard.tscn',
  'res://scenes/dev/movement_lab.tscn',
  'res://scenes/dev/movement_test.tscn',
  'res://scenes/dev/parallax_tuner.tscn',
  'res://scenes/dev/ui_designer.tscn',
  'res://scenes/dev/asteroid_lab.tscn',
  'res://scenes/dev/ui_plotter.tscn',
  'res://scenes/dev/sector_map_hd_lab.tscn',
  'res://scenes/sector_map.tscn',
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
Write-Output "------"
Write-Output "All scenes parse-clean."
exit 0
