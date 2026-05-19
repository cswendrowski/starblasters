param(
  [string]$Scenario = 'first_wave',
  [double]$Duration = 5.0,
  [switch]$UpdateBaseline,
  [switch]$UseStandalone,
  [switch]$Lint
)
# Performance harness - runs tools/perf.gd headless, parses the PERF_JSON line,
# compares to tools/perf_baseline.json, and reports regressions.
#
# Modes:
#   .\tools\perf.ps1 -Scenario first_wave           # measure mode (default)
#   .\tools\perf.ps1 -Scenario first_wave -UpdateBaseline
#   .\tools\perf.ps1 -Lint                          # static grep mode
$ErrorActionPreference = 'Stop'

$MONO_GODOT       = 'C:\Users\Cody\Downloads\Godot_v4.3-stable_mono_win64\Godot_v4.3-stable_mono_win64\Godot.exe'
$STANDALONE_GODOT = 'C:\Users\Cody\Downloads\PortalSDK(3)\Godot_v4.4.1-stable_win64.exe'
$GODOT = if ($UseStandalone) { $STANDALONE_GODOT } else { $MONO_GODOT }

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$REPO = Split-Path -Parent $scriptDir
$BASELINE = Join-Path $scriptDir 'perf_baseline.json'
$REG_FRAME_PCT = 0.20    # +20% p95 frame time = regression
$REG_NODE_DELTA_PER_SEC = 50.0  # node count climbing >50/sec = leak signal (absolute)

# Budget targets (informational - not failure conditions on their own).
$BUDGET_P95_MS = 13.0    # 60fps with headroom

# -----------------------------------------------------------------------------
# Lint mode - static grep for known shmup perf footguns.
# -----------------------------------------------------------------------------
if ($Lint) {
  Write-Output "PERF LINT - scanning scripts/"
  $hotFiles = @(
    'scripts/player.gd',
    'scripts/levels/director.gd'
  ) + (Get-ChildItem -Path (Join-Path $REPO 'scripts/enemies') -Filter '*.gd' -Recurse | ForEach-Object { $_.FullName }) `
    + (Get-ChildItem -Path (Join-Path $REPO 'scripts/projectiles') -Filter '*.gd' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })

  $warnings = New-Object System.Collections.ArrayList

  function Find-InProcess($file, $pattern, $why) {
    $content = Get-Content $file -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return }
    # Locate _process / _physics_process function bodies, then grep inside.
    $blocks = [regex]::Matches($content, '(?ms)^func _(?:physics_)?process\([^\)]*\)[^\n]*\n((?:[ \t]+[^\n]*\n)+)')
    foreach ($b in $blocks) {
      $body = $b.Groups[1].Value
      $bodyStart = $b.Index + $b.Groups[1].Index
      $rx = [regex]::Matches($body, $pattern)
      foreach ($m in $rx) {
        # Translate offset back to a line number.
        $abs = $bodyStart + $m.Index
        $line = ($content.Substring(0, $abs) -split "`n").Count
        $null = $warnings.Add([pscustomobject]@{File=$file; Line=$line; Pattern=$why; Match=$m.Value.Trim()})
      }
    }
  }

  foreach ($f in $hotFiles | Where-Object { Test-Path $_ }) {
    $relFile = Resolve-Path $f -Relative
    Find-InProcess $f 'get_tree\(\)\.get_nodes_in_group\(' 'group scan in _process'
    Find-InProcess $f '\.instantiate\(\)' 'instantiate() in _process'
    Find-InProcess $f '\bfind_(node|child)\b' 'find_node/find_child in _process'
    # print/printerr in hot paths - file-level, not _process-only.
    $hits = Select-String -Path $f -Pattern '^\s*(print|printerr)\(' -AllMatches -ErrorAction SilentlyContinue
    foreach ($h in $hits) {
      $null = $warnings.Add([pscustomobject]@{File=$f; Line=$h.LineNumber; Pattern='print/printerr in hot path'; Match=$h.Line.Trim()})
    }
  }

  # create_tween() not stored - grep across whole scripts dir.
  $allScripts = Get-ChildItem -Path (Join-Path $REPO 'scripts') -Filter '*.gd' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
  $tweenHits = Select-String -Path $allScripts -Pattern 'create_tween\(\)' -AllMatches -ErrorAction SilentlyContinue
  foreach ($h in $tweenHits) {
    if ($h.Line -notmatch '=\s*create_tween') {
      $null = $warnings.Add([pscustomobject]@{File=$h.Path; Line=$h.LineNumber; Pattern='create_tween() result not stored'; Match=$h.Line.Trim()})
    }
  }

  if ($warnings.Count -eq 0) {
    Write-Output "PERF LINT: clean"
    exit 0
  }
  Write-Output "PERF LINT - $($warnings.Count) warnings"
  foreach ($w in $warnings) {
    $rel = $w.File
    if ($rel.StartsWith($REPO)) { $rel = $rel.Substring($REPO.Length + 1) }
    Write-Output ("  {0}:{1} - {2} - {3}" -f $rel, $w.Line, $w.Pattern, $w.Match)
  }
  # Lint is warn-only; exit 0 even on warnings.
  exit 0
}

# -----------------------------------------------------------------------------
# Measure mode.
# -----------------------------------------------------------------------------
if (-not (Test-Path $GODOT)) { throw "Godot not found at $GODOT" }

$env:PERF_DURATION = $Duration.ToString()
$env:PERF_SCENARIO = $Scenario

Write-Output "[perf] scenario=$Scenario duration=${Duration}s"

$tmpOut = New-TemporaryFile
$tmpErr = New-TemporaryFile
$proc = Start-Process -FilePath $GODOT `
  -ArgumentList @('--path', $REPO, '--headless', '--script', 'res://tools/perf.gd') `
  -NoNewWindow -Wait -PassThru `
  -RedirectStandardOutput $tmpOut.FullName `
  -RedirectStandardError $tmpErr.FullName
$exit = $proc.ExitCode
$stdout = Get-Content $tmpOut.FullName -Raw -ErrorAction SilentlyContinue
$stderr = Get-Content $tmpErr.FullName -Raw -ErrorAction SilentlyContinue
Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
if ($null -eq $stdout) { $stdout = '' }
if ($null -eq $stderr) { $stderr = '' }

# Pull the PERF_JSON line.
$jsonLine = ($stdout -split "`r?`n" | Where-Object { $_ -match '^PERF_JSON:' } | Select-Object -First 1)
if (-not $jsonLine) {
  Write-Output "--- godot stdout ---"
  Write-Output $stdout
  Write-Output "--- godot stderr ---"
  Write-Output $stderr
  Write-Output "PERF: FAIL - harness did not emit PERF_JSON"
  exit 1
}
$json = $jsonLine -replace '^PERF_JSON:\s*', ''
try {
  $r = $json | ConvertFrom-Json
} catch {
  Write-Output "PERF: FAIL - could not parse PERF_JSON: $json"
  exit 1
}

Write-Output ""
Write-Output ("PERF MEASURE - scenario={0} duration={1}s samples={2}" -f $r.scenario, $r.duration, $r.samples)
Write-Output ("  frame_ms:   p50={0:F2}  p95={1:F2}  max={2:F2}" -f $r.frame_ms_p50, $r.frame_ms_p95, $r.frame_ms_max)
Write-Output ("  nodes:      peak={0}   delta={1:F1}/s" -f $r.node_peak, $r.node_delta_per_sec)
if ($r.headless_no_render) {
  Write-Output "  draw_calls: n/a (headless render server returns 0)"
  Write-Output "  primitives: n/a (headless render server returns 0)"
} else {
  Write-Output ("  draw_calls: peak={0}" -f $r.draw_calls_peak)
  Write-Output ("  primitives: peak={0}" -f $r.primitives_peak)
}
Write-Output ("  memory_mb:  static_peak={0:F1}" -f $r.memory_mb_peak)

# Budget headroom report (informational).
$pctOfBudget = ($r.frame_ms_p95 / $BUDGET_P95_MS) * 100.0
Write-Output ("  budget:     p95 at {0:F0}% of {1}ms 60fps-headroom budget" -f $pctOfBudget, $BUDGET_P95_MS)

# Baseline read / write / compare. Recompute the path locally because
# $BASELINE has been observed to come back empty later in the script under
# some PS 5.1 invocations.
$baselinePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'perf_baseline.json'
$baseline = $null
if (Test-Path $baselinePath) {
  try {
    $baselineDoc = Get-Content $baselinePath -Raw | ConvertFrom-Json
    if ($baselineDoc.PSObject.Properties.Name -contains $Scenario) {
      $baseline = $baselineDoc.$Scenario
    }
  } catch { }
}

if ($UpdateBaseline) {
  if (-not $baselineDoc) { $baselineDoc = [pscustomobject]@{} }
  $entry = [pscustomobject]@{
    frame_ms_p50 = [double]$r.frame_ms_p50
    frame_ms_p95 = [double]$r.frame_ms_p95
    frame_ms_max = [double]$r.frame_ms_max
    node_peak = [int]$r.node_peak
    draw_calls_peak = [int]$r.draw_calls_peak
    primitives_peak = [int]$r.primitives_peak
    memory_mb_peak = [double]$r.memory_mb_peak
    recorded_at = (Get-Date).ToString('s')
  }
  $baselineDoc | Add-Member -Force -NotePropertyName $Scenario -NotePropertyValue $entry
  # Recompute path locally — Set-Content seems to lose binding to script-scope
  # variables in some PS 5.1 configurations.
  $baselineOut = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'perf_baseline.json'
  $jsonText = $baselineDoc | ConvertTo-Json -Depth 4
  [System.IO.File]::WriteAllText($baselineOut, $jsonText, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ""
  Write-Output "BASELINE: updated for scenario=$Scenario in $baselineOut"
  exit 0
}

if (-not $baseline) {
  Write-Output ""
  Write-Output "PERF: pass (no baseline for $Scenario - run with -UpdateBaseline to record one)"
  exit 0
}

# Compare to baseline.
$regressions = @()
$p95Delta = ($r.frame_ms_p95 - $baseline.frame_ms_p95) / [Math]::Max($baseline.frame_ms_p95, 0.01)
if ($p95Delta -gt $REG_FRAME_PCT) {
  $regressions += ("p95 frame_ms {0:F2} -> {1:F2} ({2:P1} over baseline, threshold {3:P0})" -f $baseline.frame_ms_p95, $r.frame_ms_p95, $p95Delta, $REG_FRAME_PCT)
}
if ($r.node_delta_per_sec -gt $REG_NODE_DELTA_PER_SEC) {
  $regressions += ("node count climbing {0:F1}/s (threshold {1}/s) - leak signal" -f $r.node_delta_per_sec, $REG_NODE_DELTA_PER_SEC)
}

Write-Output ""
Write-Output ("  baseline p95={0:F2}ms (recorded {1})" -f $baseline.frame_ms_p95, $baseline.recorded_at)

if ($regressions.Count -eq 0) {
  Write-Output "PERF: pass"
  exit 0
}
Write-Output "PERF: REGRESSION"
foreach ($reg in $regressions) { Write-Output "  - $reg" }
exit 1
