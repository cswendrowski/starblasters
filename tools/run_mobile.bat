@echo off
REM Mobile renderer (Vulkan "Forward Mobile") — drops the 3D GI/SSAO/SSR/SDFGI pipeline suite that
REM Forward+ compiles (the known Godot 4.6 crash surface, #116172), keeps 2D + glow + hdr_2d.
REM This is the right renderer for a 2D game AND the best crash workaround. Double-click to test.
set "GODOT=E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe"
set "PROJ=E:\Godot-Projects\starblasters"
set "LOG=%USERPROFILE%\Desktop\sb_mobile.txt"
echo Launching Starblaster  [Mobile / Forward Mobile (Vulkan)]
echo Play through several combats. If it stops crashing, this is the fix. Log: %LOG%
echo.
"%GODOT%" --path "%PROJ%" --verbose --accurate-breadcrumbs --rendering-method mobile > "%LOG%" 2>&1
echo.
echo === crash markers in the log ===
findstr /I /C:"signal 11" /C:"CrashHandlerException" /C:"device was lost" /C:"VK_ERROR" /C:"SCRIPT ERROR" "%LOG%"
echo.
echo Full log saved at: %LOG%   (send me this file if it crashed)
pause
