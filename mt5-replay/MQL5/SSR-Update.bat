@echo off
setlocal enabledelayedexpansion
title SS Replay - Update

REM ---------------------------------------------------------------
REM  Put this file in your MQL5 folder (next to Include, Scripts,
REM  Experts, Indicators, Services). Close MetaTrader AND MetaEditor,
REM  then run it and give it the new SSReplay ZIP.
REM
REM  It touches NOTHING except the SSReplay folders and SSR*.ex5.
REM  Every deletion is printed before it happens.
REM ---------------------------------------------------------------

cd /d "%~dp0"

if not exist "Include\" goto notmql5
if not exist "Scripts\" goto notmql5

echo.
echo   MQL5 folder : %CD%
echo.

REM --- MetaTrader must be closed or the .ex5 files are locked
tasklist /fi "imagename eq terminal64.exe" 2>nul | find /i "terminal64.exe" >nul
if not errorlevel 1 (
  echo   [STOP] MetaTrader is still running. Close it and run this again.
  echo.
  pause
  exit /b 1
)
tasklist /fi "imagename eq metaeditor64.exe" 2>nul | find /i "metaeditor64.exe" >nul
if not errorlevel 1 (
  echo   [STOP] MetaEditor is still running. Close it and run this again.
  echo.
  pause
  exit /b 1
)

set "ZIP=%~1"
if "%ZIP%"=="" (
  echo   Drag the SSReplay ZIP onto this window and press Enter
  echo   ^(or just press Enter to only clean, without installing^)
  echo.
  set /p "ZIP=  ZIP: "
)
set "ZIP=%ZIP:"=%"

if not "%ZIP%"=="" (
  if not exist "%ZIP%" (
    echo.
    echo   [STOP] Not found: %ZIP%
    echo.
    pause
    exit /b 1
  )
)

echo.
echo   --- removing the old build ---

for %%D in (Include Scripts Experts Indicators Services) do (
  if exist "%%D\SSReplay\" (
    echo     delete  %%D\SSReplay
    rmdir /s /q "%%D\SSReplay"
  )
)

REM --- compiled leftovers are the reason a "new" build can run as the old one
set /a GONE=0
for %%D in (Scripts Experts Indicators Services) do (
  if exist "%%D\" (
    for /r "%%D" %%F in (SSR*.ex5) do (
      echo     delete  %%~nxF
      del /q "%%F" 2>nul
      set /a GONE+=1
    )
  )
)
echo     %GONE% stale .ex5 removed

if "%ZIP%"=="" (
  echo.
  echo   Cleaned. No ZIP given, so nothing was installed.
  echo.
  pause
  exit /b 0
)

echo.
echo   --- installing ---
echo     from  %ZIP%

REM --- the ZIP contains an MQL5\ folder, so it unpacks one level up
powershell -NoProfile -Command ^
  "try { Expand-Archive -LiteralPath '%ZIP%' -DestinationPath '%CD%\..' -Force; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"

if errorlevel 1 (
  echo.
  echo   [STOP] Extract failed. Unpack the ZIP by hand into:
  echo          %CD%\..
  echo.
  pause
  exit /b 1
)

echo.
if exist "Include\SSReplay\Common\SSR_Types.mqh" (
  echo   installed build:
  findstr /c:"#define SSR_BUILD" "Include\SSReplay\Common\SSR_Types.mqh"
) else (
  echo   [WARN] Include\SSReplay is missing after extract - check the ZIP layout.
)

echo.
echo   Done. Now:
echo     1. open MetaEditor
echo     2. Compile All  ^(Ctrl+F7^)
echo     3. run SSR_Z_Cleanup, then SSR_QA_Preflight
echo     4. check the build: line matches what is printed above
echo.
pause
exit /b 0

:notmql5
echo.
echo   [STOP] This is not an MQL5 folder.
echo          Put SSR-Update.bat next to Include\ and Scripts\, then run it.
echo          Current folder: %CD%
echo.
pause
exit /b 1
