@echo off
REM Forward+ on the D3D12 driver (keeps all visuals, swaps Vulkan->DX12). Double-click to run.
REM If crashes STOP in this mode => it's the Vulkan driver (update NVIDIA drivers).
set "GODOT=E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe"
set "PROJ=E:\Godot-Projects\starblasters"
set "LOG=%USERPROFILE%\Desktop\sb_d3d12.txt"
echo Launching Starblaster  [Forward+ / D3D12]
echo Play until it crashes, or quit the game normally. Log: %LOG%
echo.
"%GODOT%" --path "%PROJ%" --verbose --accurate-breadcrumbs --rendering-driver d3d12 > "%LOG%" 2>&1
echo.
echo === Vulkan / crash markers in the log ===
findstr /I /C:"vkCreateGraphicsPipelines" /C:"device was lost" /C:"VK_ERROR_DEVICE_LOST" /C:"fence_wait" /C:"Fossilize" /C:"signal 11" /C:"CrashHandlerException" /C:"SCRIPT ERROR" "%LOG%"
echo.
echo Full log saved at: %LOG%   (send me this file if it crashed)
pause
