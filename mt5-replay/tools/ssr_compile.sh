#!/usr/bin/env bash
#+------------------------------------------------------------------+
#| Compile every MQL5 entry point, here, without a Windows machine. |
#|                                                                  |
#| MetaEditor is a Windows binary and there is no other MQL5        |
#| compiler, so it runs under Wine. It needs no licence, no broker  |
#| and no terminal to compile - only the source tree laid out the   |
#| way MetaTrader lays it out, which is what the staging step does. |
#|                                                                  |
#| MetaEditor64.exe is MetaQuotes' and is NOT in this repository.   |
#| Point ME at your own copy:                                       |
#|                                                                  |
#|   ME=/path/to/MetaEditor64.exe tools/ssr_compile.sh              |
#|                                                                  |
#| One-time setup on a bare machine:                                |
#|   apt-get install -y wine64 xvfb                                 |
#|   WINEPREFIX=~/.wine-mt5 wineboot -u                             |
#+------------------------------------------------------------------+
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ME="${ME:-$ROOT/../.metaeditor/MetaEditor64.exe}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-mt5}"
export WINEDEBUG=-all
STAGE="$WINEPREFIX/drive_c/mt5"

if [ ! -f "$ME" ]; then
   echo "MetaEditor64.exe not found at: $ME"
   echo "Set ME=/path/to/MetaEditor64.exe"
   exit 2
fi

#--- MetaEditor resolves every include by walking up to the MQL5 root,
#--- so the tree has to sit at C:\mt5\MQL5 exactly as MetaTrader has it
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -r "$ROOT/MQL5" "$STAGE/"
cp "$ME" "$STAGE/MetaEditor64.exe"

only="${1:-}"
fail=0; pass=0
while IFS= read -r rel; do
   [ -n "$only" ] && case "$rel" in *"$only"*) ;; *) continue ;; esac
   win="C:\\mt5\\MQL5\\$(echo "$rel" | tr '/' '\\')"
   rm -f "$STAGE/out.log"
   ( cd "$STAGE" && timeout 600 xvfb-run -a wine MetaEditor64.exe \
        /compile:"$win" /log:"C:\\mt5\\out.log" >/dev/null 2>&1 )
   res=$(iconv -f UTF-16LE -t UTF-8 "$STAGE/out.log" 2>/dev/null | grep -a "^Result:" | tail -1)
   errs=$(iconv -f UTF-16LE -t UTF-8 "$STAGE/out.log" 2>/dev/null | grep -a ": error\|: warning")
   if echo "$res" | grep -q "^Result: 0 errors, 0 warnings"; then
      printf '  ok    %-52s %s\n' "$rel" "$(echo "$res" | sed 's/Result: //')"
      pass=$((pass+1))
   else
      printf '  FAIL  %-52s %s\n' "$rel" "$(echo "$res" | sed 's/Result: //')"
      echo "$errs" | sed 's|C:\\mt5\\MQL5\\|        |' | head -20
      fail=$((fail+1))
   fi
done < <(cd "$ROOT/MQL5" && find . -name '*.mq5' | sed 's|^\./||' | sort)

echo
echo "$pass clean, $fail with errors or warnings"
[ "$fail" -eq 0 ]
