@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-release.ps1" %*
set "BUILD_EXIT=%ERRORLEVEL%"
echo.
if not "%BUILD_EXIT%"=="0" echo Packaging failed. Exit code: %BUILD_EXIT%
pause
exit /b %BUILD_EXIT%
