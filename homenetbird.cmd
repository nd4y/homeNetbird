@echo off
setlocal
if not defined NETBIRD_HOME_BINARY if exist "%ProgramFiles%\homeNetbird\netbird-home.exe" set "NETBIRD_HOME_BINARY=%ProgramFiles%\homeNetbird\netbird-home.exe"
if not defined NETBIRD_HOME_BINARY set "NETBIRD_HOME_BINARY=%ProgramFiles%\Netbird\netbird.exe"
if not defined NETBIRD_HOME_DAEMON_ADDR set "NETBIRD_HOME_DAEMON_ADDR=tcp://127.0.0.1:41732"
if not defined NETBIRD_HOME_CACHE set "NETBIRD_HOME_CACHE=%LOCALAPPDATA%\NetBirdHomeCLI"
set "APPDATA=%NETBIRD_HOME_CACHE%"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if "%~1"=="" goto status
if /I "%~1"=="up" goto up
"%NETBIRD_HOME_BINARY%" --daemon-addr "%NETBIRD_HOME_DAEMON_ADDR%" %*
exit /b %errorlevel%
:up
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Check-HomeIdentity.ps1"
if errorlevel 1 exit /b 1
"%NETBIRD_HOME_BINARY%" --daemon-addr "%NETBIRD_HOME_DAEMON_ADDR%" %*
exit /b %errorlevel%
:status
"%NETBIRD_HOME_BINARY%" --daemon-addr "%NETBIRD_HOME_DAEMON_ADDR%" status
exit /b %errorlevel%
