@echo off
rem Double-click: builds the server from the latest GSPack on CurseForge.
rem Or drag a CurseForge pack zip onto this file to build from that zip.
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-ServerPack.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-ServerPack.ps1" -Zip "%~1"
)
pause
