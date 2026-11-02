@echo off
rem Double-click: opens the menu (build/update, choose a version, start the server, ...).
rem Or drag a CurseForge pack zip onto this file to build from that zip right away.
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-ServerPack.ps1" -Menu
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-ServerPack.ps1" -Zip "%~1"
    pause
)
