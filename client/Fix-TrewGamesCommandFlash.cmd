@echo off
setlocal
set "REPAIR=%~dp0Repair-TrewGamesCommandFlash.ps1"
if not exist "%REPAIR%" (
  echo Repair-TrewGamesCommandFlash.ps1 is missing.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPAIR%"
if errorlevel 1 (
  echo.
  echo The Trew Games repair did not complete.
  pause
  exit /b 1
)
echo.
echo Repair complete. You can close this window.
pause
