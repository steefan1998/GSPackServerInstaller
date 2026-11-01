@echo off
rem Double-click: builds the server from the newest GSPack-*.zip next to this file
rem or in your Downloads folder; without one, from the latest GSPack on CurseForge.
rem Or drag a CurseForge pack zip onto this file to build from that zip.
setlocal
set "ZIP=%~1"
if not "%ZIP%"=="" goto build

rem Newest GSPack zip by date: next to this file first, then in Downloads
for /f "delims=" %%F in ('dir /b /a-d /o-d "%~dp0GSPack-*.zip" 2^>nul') do if not defined ZIP set "ZIP=%~dp0%%F"
if defined ZIP goto build
for /f "delims=" %%F in ('dir /b /a-d /o-d "%USERPROFILE%\Downloads\GSPack-*.zip" 2^>nul') do if not defined ZIP set "ZIP=%USERPROFILE%\Downloads\%%F"

:build
if defined ZIP (
    echo Using pack: %ZIP%
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-ServerPack.ps1" -Zip "%ZIP%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-ServerPack.ps1"
)
pause
