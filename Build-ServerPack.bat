@echo off
rem Sleep een CurseForge pack-zip op dit bestand, of dubbelklik en geef het pad op.
set "ZIP=%~1"
if "%ZIP%"=="" set /p "ZIP=Pad naar pack-zip: "
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-ServerPack.ps1" -Zip "%ZIP%" %2 %3 %4 %5
pause
