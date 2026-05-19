$ErrorActionPreference = 'Stop'
$GODOT = 'C:\Users\Cody\Downloads\Godot_v4.3-stable_mono_win64\Godot_v4.3-stable_mono_win64\Godot.exe'
$REPO = Split-Path -Parent $PSScriptRoot
& $GODOT --path $REPO @args
