@echo off
REM Draw-index crash repro (2026-06-22, review finding #1). Double-click to run.
REM Boots scenes/dev/draw_index_crash_lab.tscn WINDOWED on the default Forward+/Vulkan
REM renderer: it holds a dense crowd of engine-trail enemies at a shared root and kills
REM them (single + mass wipes) over and over, hunting the
REM   ERROR: Parameter "canvas_item" is null  at canvas_item_set_draw_index
REM crash. Headless CANNOT fault, so this MUST run windowed. Esc quits cleanly.
REM In-game log: %APPDATA%\Godot\app_userdata\<project>\draw_index_crash.log
set "GODOT=E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe"
set "PROJ=E:\Godot-Projects\starblasters"
set "SCENE=res://scenes/dev/draw_index_crash_lab.tscn"
set "LOG=%USERPROFILE%\Desktop\sb_drawidx.txt"
echo Launching draw-index crash repro  [Forward+ / Vulkan, WINDOWED]
echo Let it churn until it crashes (or press Esc to quit). Log: %LOG%
echo.
"%GODOT%" --path "%PROJ%" "%SCENE%" --verbose --accurate-breadcrumbs > "%LOG%" 2>&1
echo.
echo === draw-index / crash markers in the log ===
findstr /I /C:"canvas_item" /C:"set_draw_index" /C:"renderer_canvas_cull" /C:"signal 11" /C:"CrashHandlerException" /C:"SCRIPT ERROR" "%LOG%"
echo.
echo Full log saved at: %LOG%   (send me this file if it crashed)
pause
