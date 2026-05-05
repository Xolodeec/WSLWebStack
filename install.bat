@echo off
setlocal

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Run this file as Administrator.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\Install-UchetWslStack.ps1"
set EXIT_CODE=%errorlevel%
if %EXIT_CODE% neq 0 (
  echo.
  echo Installation failed with code %EXIT_CODE%.
  pause
  exit /b %EXIT_CODE%
)

echo.
echo Installation completed.
pause
