@echo off
rem Drag a CurseForge pack zip onto this file, or double-click and enter the path.
set "ZIP=%~1"
if "%ZIP%"=="" set /p "ZIP=Path to pack zip: "
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-ServerPack.ps1" -Zip "%ZIP%" %2 %3 %4 %5
pause
