@echo off
REM  SS Replay - gather the logs AFTER you have run something.
REM  Double-click this once the EA or the QA script has run.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ssr_setup.ps1" -Collect
echo.
pause
