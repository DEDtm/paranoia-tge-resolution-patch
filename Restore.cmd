@echo off
setlocal
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Patch-ParanoiaResolution.ps1" -Action Restore
set "PATCH_EXIT=%ERRORLEVEL%"
echo.
if not "%PATCH_EXIT%"=="0" echo Restore failed. See the message above.
pause
exit /b %PATCH_EXIT%
