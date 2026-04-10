@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install_vscodium_copilot_chat.ps1" %*
exit /b %ERRORLEVEL%