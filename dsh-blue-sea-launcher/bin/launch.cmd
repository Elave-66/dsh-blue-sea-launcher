@echo off
rem ============================================================
rem  dsh-blue-sea-launcher launcher wrapper
rem  Usage: launch.cmd [url] [port]
rem  Delegates to launch.ps1 (ASCII-only in commands on purpose;
rem  cmd reads this file with the console code page).
rem ============================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch.ps1" %*
set "CODE=%errorlevel%"
endlocal & exit /b %CODE%
