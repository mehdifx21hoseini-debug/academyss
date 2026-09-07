@echo off
REM  SS Replay - install and compile. Double-click this.
REM  -ExecutionPolicy Bypass is here because Windows blocks unsigned
REM  scripts by default, and this one only ever reads and copies files.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ssr_setup.ps1"
echo.
pause
