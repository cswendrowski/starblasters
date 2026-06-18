@echo off
REM Current Forward+ / Vulkan renderer (project default) + verbose capture. Double-click to run.
REM Use THIS to reproduce + capture a crash, then send me the log from your Desktop.
set "GODOT=E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe"
set "PROJ=E:\Godot-Projects\starblasters"
set "LOG=%USERPROFILE%\Desktop\sb_vulkan.txt"
echo Launching Starblaster  [Forward+ / Vulkan]
echo Play until it crashes. Log: %LOG%
echo.
"%GODOT%" --path "%PROJ%" --verbose --accurate-breadcrumbs > "%LOG%" 2>&1
echo.
echo === Vulkan / crash markers in the log ===
findstr /I /C:"vkCreateGraphicsPipelines" /C:"device was lost" /C:"VK_ERROR_DEVICE_LOST" /C:"fence_wait" /C:"Fossilize" /C:"signal 11" /C:"CrashHandlerException" /C:"SCRIPT ERROR" "%LOG%"
echo.
echo Full log saved at: %LOG%   (send me this file if it crashed)
pause
