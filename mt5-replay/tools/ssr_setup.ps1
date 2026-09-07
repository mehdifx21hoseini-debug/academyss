#Requires -Version 5.1
<#
    SS Replay - install, compile, report.

    ONE FILE, TWO RUNS.

        .\ssr_setup.ps1            installs the current build and compiles it
        .\ssr_setup.ps1 -Collect   gathers the logs after you have run something

    Everything it learns goes into ONE text file on your Desktop:
    ssr_report.txt. Send that file and nothing else.

    It never touches a chart, never places an order, and never deletes
    anything except its own temporary download.
#>

[CmdletBinding()]
param(
    [switch] $Collect,
    [string] $Zip      = "",     # a zip you already downloaded, instead of fetching one
    [string] $Terminal = "",     # the MetaTrader data folder, if it cannot be found
    [string] $Branch   = "claude/custom-candle-backtesting-tool-dfzi2u"
)

$ErrorActionPreference = "Stop"
$REPO   = "mehdifx21hoseini-debug/academyss"
#--- the Desktop, unless this machine has no idea where that is
$dest = [Environment]::GetFolderPath("Desktop")
if ([string]::IsNullOrWhiteSpace($dest) -or -not (Test-Path $dest)) { $dest = $env:USERPROFILE }
if ([string]::IsNullOrWhiteSpace($dest) -or -not (Test-Path $dest)) { $dest = $env:TEMP }
if ([string]::IsNullOrWhiteSpace($dest)) { $dest = "." }
$REPORT = Join-Path $dest "ssr_report.txt"
#--- NOT $lines. PowerShell variable names are case-insensitive, so a
#--- local `$lines = $text -split ...` two functions away silently
#--- replaced this list with a fixed-size array, and the next thing
#--- to write a line died with "Collection was of a fixed size".
$RPT  = New-Object System.Collections.ArrayList

function Say([string]$t) { Write-Host $t; [void]$RPT.Add($t) }
function Head([string]$t) { Say ""; Say ("=" * 62); Say $t; Say ("=" * 62) }
function Ok([string]$t)   { Say "  OK    $t" }
function Bad([string]$t)  { Say "  FAIL  $t" }
function Note([string]$t) { Say "        $t" }

#--- MetaTrader writes its logs in UTF-16. Reading them as anything else
#--- gives a file full of null bytes and no clue why.
function Read-Mt5Text([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return "" }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    #--- no BOM: a lot of null bytes still means UTF-16
    $nulls = 0; $n = [Math]::Min(400, $bytes.Length)
    for ($i = 1; $i -lt $n; $i += 2) { if ($bytes[$i] -eq 0) { $nulls++ } }
    if ($n -gt 20 -and $nulls -gt ($n / 4)) {
        return [System.Text.Encoding]::Unicode.GetString($bytes)
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

#+------------------------------------------------------------------+
#| WHERE METATRADER KEEPS ITS FILES.                                |
#|                                                                  |
#| Not where it is installed - where its DATA folder is, which is a |
#| hashed directory under AppData and is the thing every MQL5 path  |
#| is relative to. A machine can have several; if it does, this     |
#| says so rather than guessing and installing into the wrong one.  |
#+------------------------------------------------------------------+
function Find-DataFolder {
    if ($Terminal -ne "") {
        $c = $Terminal
        if (Test-Path (Join-Path $c "MQL5\Experts")) { return $c }
        if (Test-Path (Join-Path $c "Experts")) { return (Split-Path $c -Parent) }
        throw "The folder you passed has no MQL5\Experts inside it: $c"
    }
    $root = Join-Path $env:APPDATA "MetaQuotes\Terminal"
    if (-not (Test-Path $root)) { throw "No MetaQuotes folder at $root - is MetaTrader 5 installed for this Windows user?" }

    $found = @()
    foreach ($d in Get-ChildItem $root -Directory -ErrorAction SilentlyContinue) {
        if (Test-Path (Join-Path $d.FullName "MQL5\Experts")) { $found += $d.FullName }
    }
    if ($found.Count -eq 0) { throw "Found $root but no terminal inside it has an MQL5\Experts folder." }
    if ($found.Count -eq 1) { return $found[0] }

    #+------------------------------------------------------------------+
    #| @() AROUND THE PIPELINE, and it is not decoration.               |
    #|                                                                  |
    #| Where-Object that matches exactly ONE thing returns that thing,  |
    #| not a list containing it. A String. Its .Count is 1, so the test |
    #| below passed - and [0] then indexed the STRING and returned its  |
    #| first character.                                                 |
    #|                                                                  |
    #| This installed 118 files into a folder called "C" on a machine   |
    #| that had two terminals, reported success, and left MetaEditor    |
    #| compiling against a data folder with none of them in it. The     |
    #| report even printed "data folder   C" and nothing was watching   |
    #| for it - which is why the check at the bottom exists now.        |
    #+------------------------------------------------------------------+
    $withUs = @($found | Where-Object { Test-Path (Join-Path $_ "MQL5\Experts\SSReplay") })
    if ($withUs.Count -eq 1) { return $withUs[0] }

    Say "More than one MetaTrader data folder was found:"
    foreach ($f in $found) { Say "   $f" }
    if ($withUs.Count -gt 1) {
        Say "and more than one of them already has SS Replay in it."
    }
    throw "Run it again naming the one you use:  .\ssr_setup.ps1 -Terminal ""<path>"""
}

#+------------------------------------------------------------------+
#| NOTHING GETS COPIED SOMEWHERE THAT IS NOT A TERMINAL.            |
#|                                                                  |
#| The last line of defence, deliberately dumb: whatever path was   |
#| worked out above, it has to be absolute and it has to contain    |
#| MQL5\Experts, or nothing is written at all. A wrong install that |
#| says it worked costs far more than a refusal that says why.      |
#+------------------------------------------------------------------+
function Assert-DataFolder([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { throw "The MetaTrader data folder came back empty." }
    if ($p.Length -lt 4) { throw "The MetaTrader data folder came back as '$p', which cannot be right." }
    if (-not [System.IO.Path]::IsPathRooted($p)) { throw "'$p' is not a full path." }
    if (-not (Test-Path -LiteralPath $p)) { throw "'$p' does not exist." }
    if (-not (Test-Path -LiteralPath (Join-Path $p "MQL5\Experts"))) {
        throw "'$p' has no MQL5\Experts inside it, so it is not a MetaTrader data folder."
    }
    return $p
}

function Find-MetaEditor([string]$data) {
    #--- MetaTrader records its own install path next to the data folder
    $origin = Join-Path $data "origin.txt"
    if (Test-Path $origin) {
        $p = (Read-Mt5Text $origin).Trim() -replace "`0", ""
        if ($p -ne "") {
            foreach ($exe in @("metaeditor64.exe", "metaeditor.exe")) {
                $c = Join-Path $p $exe
                if (Test-Path $c) { return $c }
            }
        }
    }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        $hit = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -like "*MetaTrader*" } |
               ForEach-Object { Join-Path $_.FullName "metaeditor64.exe" } |
               Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return ""
}

function Build-String([string]$mql5) {
    $f = Join-Path $mql5 "Include\SSReplay\Common\SSR_Build.mqh"
    if (-not (Test-Path $f)) { return "" }
    foreach ($ln in Get-Content $f) {
        if ($ln -match '#define\s+SSR_BUILD\s+"([^"]+)"') { return $Matches[1] }
    }
    return ""
}

#+------------------------------------------------------------------+
#| INSTALL                                                          |
#+------------------------------------------------------------------+
function Do-Install {
    $data = Assert-DataFolder (Find-DataFolder)
    $mql5 = Join-Path $data "MQL5"
    Head "WHERE"
    Say "  data folder   $data"

    $was = Build-String $mql5
    Say ("  build before  " + $(if ($was -eq "") { "<SS Replay not installed yet>" } else { $was }))

    #--- the source ------------------------------------------------
    Head "FETCH"
    $tmp = Join-Path $env:TEMP ("ssr_" + [Guid]::NewGuid().ToString("N").Substring(0,8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zipPath = ""

    if ($Zip -ne "") {
        if (-not (Test-Path -LiteralPath $Zip)) { throw "No such zip: $Zip" }
        $zipPath = $Zip
        Ok "using the zip you gave me: $Zip"
    } else {
        $url = "https://github.com/$REPO/archive/refs/heads/$Branch.zip"
        Say "  $url"
        Say "  downloading about 21 MB - this is the slow part, give it a minute"
        $zipPath = Join-Path $tmp "src.zip"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $old = $ProgressPreference; $ProgressPreference = "SilentlyContinue"
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
            $ProgressPreference = $old
            Ok ("downloaded, " + [Math]::Round((Get-Item $zipPath).Length / 1MB, 2) + " MB")
        } catch {
            Bad "the download failed: $($_.Exception.Message)"
            Note "Download it yourself in a browser, then run:"
            Note "  .\ssr_setup.ps1 -Zip ""C:\path\to\the.zip"""
            return $false
        }
    }

    $out = Join-Path $tmp "x"
    #--- Expand-Archive refuses a path it cannot see as .zip
    $staged = Join-Path $tmp "src.zip"
    if ($zipPath -ne $staged) { Copy-Item -LiteralPath $zipPath -Destination $staged -Force }
    Expand-Archive -LiteralPath $staged -DestinationPath $out -Force

    $src = Get-ChildItem $out -Recurse -Directory -Filter "MQL5" -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -match "mt5-replay" } | Select-Object -First 1
    if (-not $src) { Bad "the zip has no mt5-replay\MQL5 inside it"; return $false }

    $newBuild = Build-String $src.FullName
    Say ("  build in zip  " + $(if ($newBuild -eq "") { "<could not read it>" } else { $newBuild }))

    #--- the copy --------------------------------------------------
    Head "INSTALL"
    $n = 0
    foreach ($f in Get-ChildItem $src.FullName -Recurse -File) {
        $rel = $f.FullName.Substring($src.FullName.Length).TrimStart('\')
        $dst = Join-Path $mql5 $rel
        $dir = Split-Path $dst -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
        $n++
    }
    Ok "$n files copied"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    $now = Build-String $mql5
    if ($now -eq "" -or ($newBuild -ne "" -and $now -ne $newBuild)) {
        Bad "after copying, the installed build reads '$now' - it should read '$newBuild'"
        Note "Something is blocking the write. Close MetaTrader and run this again."
        return $false
    }
    Ok "installed build is now: $now"
    if ($was -ne "" -and $was -ne $now) { Note "(it was '$was' before)" }

    #--- compile ---------------------------------------------------
    Head "COMPILE"
    $me = Find-MetaEditor $data
    if ($me -eq "") {
        Bad "MetaEditor was not found, so nothing was compiled."
        Note "Open MetaEditor yourself and press F7 on these five files:"
        foreach ($t in Get-Targets) { Note "  $t" }
        return $false
    }
    Say "  $me"
    Say ""

    $anyError = $false
    foreach ($t in Get-Targets) {
        $file = Join-Path $mql5 $t
        if (-not (Test-Path $file)) { Bad "$t - the file is not there"; $anyError = $true; continue }

        $log = [System.IO.Path]::ChangeExtension($file, ".compile.log")
        if (Test-Path $log) { Remove-Item $log -Force }

        $p = Start-Process -FilePath $me `
                           -ArgumentList "/compile:`"$file`"", "/log:`"$log`"" `
                           -NoNewWindow -Wait -PassThru
        Start-Sleep -Milliseconds 250

        $text = Read-Mt5Text $log
        $lines = $text -split "`r?`n"

        #--- MetaEditor's own summary line is the honest answer, not
        #--- the exit code, which it uses for other things too
        $summary = ($lines | Where-Object { $_ -match "\d+\s+error" } | Select-Object -Last 1)
        $errs = @($lines | Where-Object { $_ -match ":\s*error\s+\d+" })

        if ($errs.Count -eq 0) {
            Ok ("$t   " + $(if ($summary) { $summary.Trim() } else { "0 errors" }))
        } else {
            $anyError = $true
            Bad ("$t   " + $(if ($summary) { $summary.Trim() } else { "$($errs.Count) error(s)" }))
            foreach ($e in ($errs | Select-Object -First 25)) { Note $e.Trim() }
            if ($errs.Count -gt 25) { Note "... and $($errs.Count - 25) more" }
        }
        Remove-Item $log -Force -ErrorAction SilentlyContinue
    }

    Head "WHAT TO DO NEXT"
    if ($anyError) {
        Say "  Compiling failed. Send ssr_report.txt and stop here -"
        Say "  do not run anything in MetaTrader yet."
        return $false
    }
    Say "  1. In MetaTrader, REMOVE the EA from the chart and drag it on again."
    Say "     Recompiling does not change an EA that is already running."
    Say "  2. Run the script SSR_QA_Smoke on any chart."
    Say "  3. Then double-click this file again with -Collect:"
    Say "        .\ssr_setup.ps1 -Collect"
    Say "     and send the ssr_report.txt it writes."
    return $true
}

function Get-Targets {
    @(
        "Experts\SSReplay\SSReplayStandalone.mq5",
        "Scripts\SSReplay\QA\SSR_QA_Smoke.mq5",
        "Scripts\SSReplay\QA\SSR_QA_Preflight.mq5",
        "Scripts\SSReplay\QA\SSR_QA_FontProbe.mq5",
        "Scripts\SSReplay\SSR_ClassReport.mq5"
    )
}

#+------------------------------------------------------------------+
#| COLLECT                                                          |
#|                                                                  |
#| Everything that says what actually happened, in one place: the   |
#| build that ran, the lines this project printed, and the pass and |
#| fail counts. The log is filtered to our own lines - a raw MT5    |
#| log is mostly the terminal talking to its broker.                |
#+------------------------------------------------------------------+
function Do-Collect {
    $data = Assert-DataFolder (Find-DataFolder)
    $mql5 = Join-Path $data "MQL5"
    Head "WHERE"
    Say "  data folder   $data"
    Say ("  installed     " + $(Build-String $mql5))

    $logDir = Join-Path $mql5 "Logs"
    if (-not (Test-Path $logDir)) { Bad "no MQL5\Logs folder - has anything been run yet?"; return }

    $log = Get-ChildItem $logDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $log) { Bad "MQL5\Logs is empty - run the EA or the QA script first."; return }

    Head "LOG"
    Say "  $($log.Name)   last written $($log.LastWriteTime)"

    $text  = Read-Mt5Text $log.FullName
    $lines = $text -split "`r?`n"

    #--- ours only: everything this project prints is tagged
    $ours = @($lines | Where-Object {
        $_ -match "\[host\]|\[news\]|\[panel\]|\[sink\]|SS Replay|PASS |FAIL |=== " })

    if ($ours.Count -eq 0) {
        Bad "that log has no SS Replay lines in it at all."
        Note "Either nothing was run today, or MetaTrader is writing to a"
        Note "different data folder than the one this installed into."
        return
    }

    #--- the three questions worth answering before anyone reads it
    Head "ANSWERS"
    $build = ($ours | Where-Object { $_ -match "SS Replay build v(\d+)" } | Select-Object -Last 1)
    $ver = 0
    if ($build -and $build -match "SS Replay build v(\d+)") { $ver = [int]$Matches[1] }
    if ($build) { Say "  build that RAN : $($build.Trim())" } else { Say "  build that RAN : <the EA did not start>" }

    #--- the installed tree and the running binary are different things:
    #--- recompiling does not change an EA that is already on a chart
    $onDisk = Build-String $mql5
    if ($onDisk -match "^v(\d+)" -and $ver -gt 0 -and [int]$Matches[1] -ne $ver) {
        Bad "the RUNNING build (v$ver) is not the INSTALLED one ($onDisk)"
        Note "Remove the EA from the chart and drag it on again."
    }

    $obs = ($ours | Where-Object { $_ -match "observers watching this replay" } | Select-Object -Last 1)
    if ($obs)          { Ok  "observers      : $($obs.Trim())" }
    elseif ($ver -ge 80) { Bad "observers      : the line is MISSING and v$ver should print it" }
    elseif ($ver -gt 0)  { Note "observers      : v$ver is too old to print it - install and recompile" }
    else               { Note "observers      : the EA did not run on this log" }

    $refused = @($ours | Where-Object { $_ -match "OBSERVER REFUSED" })
    if ($refused.Count -gt 0) { foreach ($r in $refused) { Bad $r.Trim() } }

    #+------------------------------------------------------------------+
    #| -cmatch, NOT -match. PowerShell compares case-insensitively by    |
    #| default, and the EA's own banner line carries "pass=1" for which  |
    #| pass of the handover it is on. Counted case-insensitively, every  |
    #| single run reported one or two QA passes that never happened -    |
    #| and a report that inflates its own good news is worse than none.  |
    #+------------------------------------------------------------------+
    $pass = @($ours | Where-Object { $_ -cmatch "\bPASS\b" }).Count
    $fail = @($ours | Where-Object { $_ -cmatch "\bFAIL\b" }).Count
    if ($pass + $fail -gt 0) {
        Say "  QA             : $pass passed, $fail failed"
        if ($fail -gt 0) {
            Say ""
            foreach ($f in ($ours | Where-Object { $_ -cmatch "\bFAIL\b" })) { Bad $f.Trim() }
        }
    } else {
        Note "QA             : the smoke test has not been run on this log"
    }

    Head "EVERY SS REPLAY LINE ($($ours.Count))"
    foreach ($l in $ours) { [void]$RPT.Add($l.TrimEnd()) }
}

#+------------------------------------------------------------------+
#| MAIN                                                             |
#+------------------------------------------------------------------+
#+------------------------------------------------------------------+
#| SAY SOMETHING BEFORE DOING ANYTHING.                             |
#|                                                                  |
#| These three lines used to go into the report buffer and not to   |
#| the screen, so the first thing a person saw was the WHERE block  |
#| after the terminal folder had been hunted down. On a machine     |
#| where that hunt is slow, or the script never loaded at all, the  |
#| window looked identical: empty. "Did it start?" and "did it      |
#| finish?" need different answers, so it now says hello first.     |
#+------------------------------------------------------------------+
Say "SS Replay setup report"
Say ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + "   mode=" + $(if ($Collect) { "collect" } else { "install" }))
Say ("windows " + [Environment]::OSVersion.Version + "   powershell " + $PSVersionTable.PSVersion)
Say "working..."

$failed = $false
try {
    if ($Collect) { Do-Collect } else { if (-not (Do-Install)) { $failed = $true } }
} catch {
    Bad "STOPPED: $($_.Exception.Message)"
    $failed = $true
}

try {
    $RPT | Set-Content -LiteralPath $REPORT -Encoding UTF8
    Write-Host ""
    Write-Host "Report written to: $REPORT" -ForegroundColor Cyan
    Write-Host "Send that file." -ForegroundColor Cyan
} catch {
    Write-Host "Could not write the report to the Desktop: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Copy the text above instead."
}

#--- the pause lives in the .bat, so this file can also be run from a
#--- console or a script without hanging on a prompt nobody will answer
if ($failed) { exit 1 }
