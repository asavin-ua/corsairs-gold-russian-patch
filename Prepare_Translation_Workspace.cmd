@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Prepare-TranslationWorkspace.ps1"
if errorlevel 1 echo Workspace preparation failed.
echo.
pause
