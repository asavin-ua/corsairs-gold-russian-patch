@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-RussianPatch.ps1" -Mode Uninstall
if errorlevel 1 echo Restoration failed. The backup folder was not deleted.
echo.
pause
