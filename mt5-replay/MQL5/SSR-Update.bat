@echo off
setlocal enabledelayedexpansion
title SS Replay - Update
color 0F

REM ---------------------------------------------------------------
REM  Put this file in your MQL5 folder (next to Include, Scripts,
REM  Experts, Indicators, Services). Close MetaTrader AND MetaEditor,
REM  then double-click it.
REM
REM  It finds the newest SSReplay ZIP in Downloads, removes the old
REM  build, installs the new one, and compiles it.
REM
REM  It touches NOTHING except the SSReplay folders and SSR*.ex5.
REM ---------------------------------------------------------------

cd /d "%~dp0"
set "TMPF=%TEMP%\ssr_update_tmp.txt"

REM ---------------------------------------------------------------
REM  IS THIS THE TERMINAL'S MQL5 FOLDER, OR THE ZIP'S?
REM
REM  Include\ and Scripts\ are not enough to tell them apart - the
REM  ZIP contains an MQL5 folder with exactly those names, so running
REM  this file from an unpacked ZIP passed every check and quietly
REM  reinstalled the build on top of itself while the terminal kept
REM  running the old one.
REM
REM  The parent settles it. A MetaTrader data folder always carries
REM  origin.txt, config\ and profiles\ beside MQL5. An unpacked ZIP
REM  carries none of them.
REM ---------------------------------------------------------------
if not exist "Include" goto notmql5
if not exist "Scripts" goto notmql5

set "ISDATA="
if exist "..\origin.txt" set "ISDATA=1"
if exist "..\config"     set "ISDATA=1"
if exist "..\profiles"   set "ISDATA=1"
if not defined ISDATA goto notterminal

echo.
echo   ===============================================
echo     SS Replay - Update
echo   ===============================================
echo.
echo   MQL5 folder : %CD%
echo.

REM --- both programs hold the files open
tasklist /fi "imagename eq terminal64.exe" 2>nul | find /i "terminal64.exe" >nul
if not errorlevel 1 (
  echo   [STOP] MetaTrader is still running. Close it and run this again.
  goto fail
)
tasklist /fi "imagename eq metaeditor64.exe" 2>nul | find /i "metaeditor64.exe" >nul
if not errorlevel 1 (
  echo   [STOP] MetaEditor is still running. Close it and run this again.
  goto fail
)

REM ---------------------------------------------------------------
REM  Find the ZIP.
REM
REM  An empty answer used to mean "clean, install nothing". It ended
REM  with the same pause as a success, so pressing Enter looked like
REM  an install and silently left the old build running for a whole
REM  round of tests. Enter now means "yes, install that one".
REM ---------------------------------------------------------------
set "ZIP=%~1"

if "%ZIP%"=="" (
  del /q "%TMPF%" 2>nul
  powershell -NoProfile -Command "$c=@(); foreach($d in @(\"$env:USERPROFILE\Downloads\", (Get-Location).Path, (Split-Path (Get-Location).Path))) { if (Test-Path -LiteralPath $d) { $c += Get-ChildItem -LiteralPath $d -Filter 'SSReplay*.zip' -File -ErrorAction SilentlyContinue } }; $n = $c | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($n) { Set-Content -LiteralPath $env:TEMP'\ssr_update_tmp.txt' -Value $n.FullName }"
  if exist "%TMPF%" set /p ZIP=<"%TMPF%"
  del /q "%TMPF%" 2>nul
)

if not "%ZIP%"=="" (
  echo   Found this ZIP:
  echo       %ZIP%
  echo.
  set "ANS="
  set /p "ANS=  Press Enter to install it, or paste a different path: "
  if not "!ANS!"=="" set "ZIP=!ANS!"
) else (
  echo   No SSReplay ZIP found in your Downloads folder.
  echo.
  set "ZIP="
  set /p "ZIP=  Drag the ZIP onto this window, then press Enter: "
)

set "ZIP=%ZIP:"=%"

if "%ZIP%"=="" (
  echo.
  echo   [STOP] No ZIP given. Nothing was changed.
  goto fail
)
if not exist "%ZIP%" (
  echo.
  echo   [STOP] Not found: %ZIP%
  echo          Nothing was changed.
  goto fail
)

echo.
echo   --- removing the old build ---

for %%D in (Include Scripts Experts Indicators Services) do (
  if exist "%%D\SSReplay\" (
    echo     delete  %%D\SSReplay
    rmdir /s /q "%%D\SSReplay"
  )
)

REM --- stale .ex5 are why a "new" build can still run as the old one
set /a GONE=0
for %%D in (Scripts Experts Indicators Services) do (
  if exist "%%D\" (
    for /r "%%D" %%F in (SSR*.ex5) do (
      del /q "%%F" 2>nul
      set /a GONE+=1
    )
  )
)
echo     %GONE% stale .ex5 removed

echo.
echo   --- installing ---
echo     from  %ZIP%

powershell -NoProfile -Command "try { Expand-Archive -LiteralPath '%ZIP%' -DestinationPath (Split-Path (Get-Location).Path) -Force; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"

if errorlevel 1 (
  echo.
  echo   [STOP] Extract failed. Unpack the ZIP by hand into:
  echo          %CD%\..
  goto fail
)

if not exist "Include\SSReplay\Common\SSR_Build.mqh" (
  echo.
  echo   [STOP] Include\SSReplay is missing after the extract.
  echo          The ZIP layout is not what was expected.
  goto fail
)

echo.
echo   --- installed build ---
findstr /c:"#define SSR_BUILD" "Include\SSReplay\Common\SSR_Build.mqh"

REM ---------------------------------------------------------------
REM  Compile here rather than leaving it as a step to remember.
REM  Forgetting it produces exactly the same symptom as a failed
REM  install: new source on disk, old .ex5 still running.
REM  origin.txt in the data folder holds the terminal's install path.
REM ---------------------------------------------------------------
echo.
echo   --- compiling ---

set "MEDIT="
del /q "%TMPF%" 2>nul
powershell -NoProfile -Command "$o = Join-Path (Split-Path (Get-Location).Path) 'origin.txt'; $e = $null; if (Test-Path -LiteralPath $o) { $p = (Get-Content -LiteralPath $o -Raw).Trim(); $c = Join-Path $p 'metaeditor64.exe'; if (Test-Path -LiteralPath $c) { $e = $c } }; if (-not $e) { foreach ($r in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) { if ($r -and -not $e) { $h = Get-ChildItem -LiteralPath $r -Filter 'metaeditor64.exe' -Recurse -Depth 3 -File -ErrorAction SilentlyContinue | Select-Object -First 1; if ($h) { $e = $h.FullName } } } }; if ($e) { Set-Content -LiteralPath $env:TEMP'\ssr_update_tmp.txt' -Value $e }"
if exist "%TMPF%" set /p MEDIT=<"%TMPF%"
del /q "%TMPF%" 2>nul

if "%MEDIT%"=="" (
  echo     [WARN] MetaEditor was not found automatically.
  echo            Open MetaEditor and press Ctrl+F7 ^(Compile All^) yourself.
  goto done
)

echo     using %MEDIT%
set "CLOG=%TEMP%\ssr_compile.log"
del /q "%CLOG%" 2>nul
"%MEDIT%" /compile:"%CD%" /include:"%CD%" /log:"%CLOG%"

powershell -NoProfile -Command "$l = $env:TEMP + '\ssr_compile.log'; if (-not (Test-Path -LiteralPath $l)) { Write-Host '    (no compile log was produced)'; exit }; $t = Get-Content -LiteralPath $l; $bad = @($t | Where-Object { $_ -match 'error' -and $_ -notmatch '0 error' }); Write-Host ''; $t | Select-Object -Last 2 | ForEach-Object { Write-Host ('    ' + $_) }; if ($bad.Count -gt 0) { Write-Host ''; Write-Host '    ERRORS:'; $bad | Select-Object -First 12 | ForEach-Object { Write-Host ('    ' + $_) } } else { Write-Host ''; Write-Host '    no errors' }"

:done
echo.
echo   ===============================================
echo     DONE - the build printed above is installed
echo   ===============================================
echo.
echo   Next: in MetaTrader run SSR_Z_Cleanup, and check its first
echo         line shows that same build.
echo.
pause
exit /b 0

:fail
echo.
echo   ===============================================
echo     STOPPED - nothing was installed
echo   ===============================================
echo.
pause
exit /b 1

:notmql5
echo.
echo   [STOP] This is not an MQL5 folder.
echo          Put SSR-Update.bat next to Include and Scripts
echo          Current folder: %CD%
echo.
pause
exit /b 1

:notterminal
echo.
echo   ===============================================
echo     WRONG FOLDER - nothing was changed
echo   ===============================================
echo.
echo   This looks like the MQL5 folder from inside the ZIP,
echo   not MetaTrader's own one.
echo.
echo   Current folder:
echo       %CD%
echo.
echo   MetaTrader's data folder always has origin.txt, config and
echo   profiles beside MQL5. This folder has none of them.
echo.
echo   To find the right one:
echo       MetaTrader  File  ^>  Open Data Folder  ^>  MQL5
echo.
echo   Copy SSR-Update.bat into THAT folder and run it from there.
echo   Leave the ZIP in Downloads - it finds it by itself.
echo.
pause
exit /b 1
