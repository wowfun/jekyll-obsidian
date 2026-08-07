@echo off
setlocal EnableExtensions EnableDelayedExpansion

where pwsh.exe >nul 2>nul
if !ERRORLEVEL! EQU 0 (
  pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" %*
  exit /b !ERRORLEVEL!
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" %*
  exit /b !ERRORLEVEL!
)
