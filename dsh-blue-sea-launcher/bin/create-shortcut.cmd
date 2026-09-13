@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
echo ============================================
echo  Blue Sea Launcher - create desktop shortcut
echo ============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%create-shortcut.ps1"
set "CODE=%ERRORLEVEL%"
echo.
if "%CODE%"=="0" (
  echo Done. Look for the shortcut on your desktop / start menu.
) else (
  echo Failed with code %CODE%. See messages above.
)
echo.
pause
exit /b %CODE%
