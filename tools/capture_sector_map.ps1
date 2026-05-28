$ErrorActionPreference = 'Stop'
$STANDALONE = 'C:\Users\Cody\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe'
$REPO = Split-Path -Parent $PSScriptRoot
$SCRIPT = 'tools/capture_sector_map.gd'

if (-not (Test-Path $STANDALONE)) { 
    throw "Standalone Godot not found at $STANDALONE" 
}

Write-Output "Capturing sector map with GDScript launcher..."
# Run WITHOUT --headless to allow rendering
Start-Process -FilePath $STANDALONE -ArgumentList "--path `"$REPO`" -s $SCRIPT" -NoNewWindow -Wait

$capturesFile = "$REPO\captures\sector_map_label_review.png"
if (Test-Path $capturesFile) {
    Write-Output "Screenshot captured at: $capturesFile"
    Get-Item "$capturesFile" | Format-Table FullName, Length
} else {
    Write-Output "ERROR: Screenshot not found at $capturesFile"
}
