param(
  [double]$Duration = 5.0,
  [switch]$UseStandalone
)
# Boot smoke harness — runs tools/smoke.gd headless, then post-processes the
# log for ERROR / SCRIPT ERROR / Parser Error lines that Godot prints to
# stdout but doesn't reflect in the exit code.
#
# Exit codes:
#   0 — pass (no SMOKE_FAIL lines AND no ERROR lines in the log)
#   1 — fail (either the smoke script failed an assertion, or Godot logged errors)
#
# Usage:
#   .\tools\smoke.ps1                 # default 5s tick, uses Mono Godot (matches editor)
#   .\tools\smoke.ps1 -Duration 8     # longer tick — useful for checking wave 2
#   .\tools\smoke.ps1 -UseStandalone  # use non-Mono Godot 4.4.1 (the publish toolchain)
$ErrorActionPreference = 'Stop'

$MONO_GODOT       = 'C:\Users\Cody\Downloads\Godot_v4.3-stable_mono_win64\Godot_v4.3-stable_mono_win64\Godot.exe'
$STANDALONE_GODOT = 'C:\Users\Cody\Downloads\PortalSDK(3)\Godot_v4.4.1-stable_win64.exe'

$GODOT = if ($UseStandalone) { $STANDALONE_GODOT } else { $MONO_GODOT }
if (-not (Test-Path $GODOT)) { throw "Godot not found at $GODOT" }

$REPO = Split-Path -Parent $PSScriptRoot
$env:SMOKE_DURATION = $Duration.ToString()

Write-Output "[smoke] running tools/smoke.gd (duration=${Duration}s)"

# In PS 5.1, `2>&1` on a native exe wraps each stderr line in an ErrorRecord
# and sets $? to false even on exit 0. Redirect stderr to a temp file and
# read it back instead so the log stays clean text.
$tmpErr = New-TemporaryFile
$tmpOut = New-TemporaryFile
$proc = Start-Process -FilePath $GODOT `
  -ArgumentList @('--path', $REPO, '--headless', '--script', 'res://tools/smoke.gd') `
  -NoNewWindow -Wait -PassThru `
  -RedirectStandardOutput $tmpOut.FullName `
  -RedirectStandardError $tmpErr.FullName
$godotExit = $proc.ExitCode
$stdoutText = Get-Content $tmpOut.FullName -Raw -ErrorAction SilentlyContinue
$stderrText = Get-Content $tmpErr.FullName -Raw -ErrorAction SilentlyContinue
Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
if ($null -eq $stdoutText) { $stdoutText = '' }
if ($null -eq $stderrText) { $stderrText = '' }
$log = $stdoutText + "`n--- stderr ---`n" + $stderrText

# Show the log so failures are inspectable.
Write-Output "--- godot log ---"
Write-Output $log
Write-Output "--- end log ---"

$smokeFail = ($log -match 'SMOKE_RESULT: fail') -or ($log -match 'SMOKE_FAIL:')
$smokePass = ($log -match 'SMOKE_RESULT: pass')

# Errors Godot prints but doesn't necessarily return non-zero for. Filter
# out known engine-cleanup noise from the Mono editor build so we only
# alarm on real script/parser/runtime errors.
$ignorePatterns = @(
  'RID allocations of type .* were leaked at exit',
  'resources still in use at exit',
  'ObjectDB instances leaked at exit',
  'Nodes with non-equal opposite anchors'
)
$lines = $log -split "`r?`n"
$loggedErrors = @()
foreach ($line in $lines) {
  if ($line -notmatch '(SCRIPT ERROR:|Parser Error:|^ERROR: )') { continue }
  $skip = $false
  foreach ($ign in $ignorePatterns) {
    if ($line -match $ign) { $skip = $true; break }
  }
  if (-not $skip) { $loggedErrors += $line.Trim() }
}

$fail = $false
$reasons = @()

if (-not $smokePass) {
  $fail = $true
  $reasons += "smoke.gd did not print SMOKE_RESULT: pass"
}
if ($smokeFail) {
  $fail = $true
  $reasons += "smoke.gd asserted failure"
}
if ($loggedErrors.Count -gt 0) {
  $fail = $true
  $reasons += "godot log contains $($loggedErrors.Count) error line(s):"
  foreach ($e in $loggedErrors) { $reasons += "    $e" }
}
if ($godotExit -ne 0 -and $godotExit -ne 1) {
  # exit 1 is what smoke.gd uses for an assertion failure — already handled above.
  # Any other non-zero is a Godot-level crash.
  $fail = $true
  $reasons += "godot exited with $godotExit"
}

if ($fail) {
  Write-Output ""
  Write-Output "SMOKE: FAIL"
  foreach ($r in $reasons) { Write-Output "  - $r" }
  exit 1
}

Write-Output ""
Write-Output "SMOKE: PASS"
exit 0
