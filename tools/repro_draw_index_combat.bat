@echo off
REM Draw-index crash repro — HIGH-FIDELITY AUTO-PLAYER (2026-06-22). Double-click to run.
REM Auto-plays real combat on a loop WINDOWED on Forward+/Vulkan, as close to a real player
REM as possible: enters each level via the REAL load path (LevelLauncher -> loading screen),
REM rolls a RANDOM realistic loadout (primary + secondary + smart bomb + modules/shift/engine),
REM and drives a VULNERABLE player that sweeps the whole playfield, fires + swaps weapons +
REM focuses, takes damage, and DIES. On death or clear it skips the summary and relaunches a
REM fresh random level. Hunts the
REM   ERROR: Parameter "canvas_item" is null  at canvas_item_set_draw_index
REM crash. Headless CANNOT fault, so this MUST run windowed. Esc quits cleanly.
REM In-game log: %APPDATA%\Godot\app_userdata\<project>\draw_index_combat.log
set "GODOT=E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe"
set "PROJ=E:\Godot-Projects\starblasters"
set "SCENE=res://scenes/dev/draw_index_combat_repro.tscn"
set "LOG=%USERPROFILE%\Desktop\sb_drawidx_combat.txt"
echo Launching draw-index COMBAT repro  [Forward+ / Vulkan, WINDOWED]
echo Let it churn until it crashes (or press Esc to quit). Log: %LOG%
echo.
"%GODOT%" --path "%PROJ%" "%SCENE%" --verbose --accurate-breadcrumbs > "%LOG%" 2>&1
echo.
echo === draw-index / crash markers in the log ===
findstr /I /C:"canvas_item" /C:"set_draw_index" /C:"renderer_canvas_cull" /C:"signal 11" /C:"CrashHandlerException" /C:"SCRIPT ERROR" "%LOG%"
echo.
echo Full log saved at: %LOG%   (send me this file if it crashed)
pause
