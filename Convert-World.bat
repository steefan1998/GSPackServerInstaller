@echo off
rem Converts a GSPack world to the 0.5 material unification (one item per metal, AllTheOres ores).
rem Double-click: choose the server folder (or a world folder) in File Explorer.
rem Or drag a server folder or a world folder onto this file.
rem Stop the server first. A dry run shows what will change before anything is written.
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Convert-World.ps1" -Interactive -Pick
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Convert-World.ps1" -Interactive -World "%~1"
)
echo.
pause
