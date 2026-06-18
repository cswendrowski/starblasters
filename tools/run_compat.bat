@echo off
REM Compatibility (OpenGL) renderer (drops hdr_2d glow / bloom). Double-click to run.
REM If crashes STOP here but D3D12 also crashed => it's the Forward+ render path (Godot version).
set "GODOT=E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe"
set "PROJ=E:\Godot-Projects\starblasters"
set "LOG=%USERPROFILE%\Desktop\sb_compat.txt"
echo Launching Starblaster  [Compatibility / OpenGL]
echo Play until it crashes, or quit normally. Log: %LOG%
echo.
"%GODOT%" --path "%PROJ%" --verbose --accurate-breadcrumbs --rendering-method gl_compatibility > "%LOG%" 2>&1
echo.
echo === Vulkan / crash markers in the log ===
findstr /I /C:"vkCreateGraphicsPipelines" /C:"device was lost" /C:"VK_ERROR_DEVICE_LOST" /C:"fence_wait" /C:"Fossilize" /C:"signal 11" /C:"CrashHandlerException" /C:"SCRIPT ERROR" "%LOG%"
echo.
echo Full log saved at: %LOG%   (send me this file if it crashed)
pause
