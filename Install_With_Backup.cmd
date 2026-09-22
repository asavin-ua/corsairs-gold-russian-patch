@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-RussianPatch.ps1" -Mode Install -CreateBackup
if errorlevel 1 (
  echo.
  echo Installation failed. If the game is under Program Files, run this file as Administrator.
)
echo.
pause
