@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Setup.ps1"
exit /b %errorlevel%
