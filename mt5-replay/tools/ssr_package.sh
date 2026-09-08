#!/usr/bin/env bash
#+------------------------------------------------------------------+
#| Build the one file the user installs.                            |
#|                                                                  |
#| Sending individual .ex5 files cost a day: versions mixed on the  |
#| user's machine until nothing agreed with anything. One archive,  |
#| whole tree, every entry point compiled, replaces the lot         |
#| whatever state it is in.                                         |
#|                                                                  |
#|   ME=/path/to/MetaEditor64.exe tools/ssr_package.sh              |
#+------------------------------------------------------------------+
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/../SSReplay.zip}"
STAGE="${WINEPREFIX:-$HOME/.wine-mt5}/drive_c/mt5"

"$ROOT/tools/ssr_compile.sh"

BUILD=$(sed -n 's/.*SSR_BUILD *"\([^ ]*\).*/\1/p' \
        "$ROOT/MQL5/Include/SSReplay/Common/SSR_Build.mqh")
OUT="${OUT%.zip}-$BUILD.zip"

TMP=$(mktemp -d)
cp -r "$STAGE/MQL5" "$TMP/"
find "$TMP" -name '*.compile.log' -delete
rm -f "$OUT"
( cd "$TMP" && zip -qr "$OUT" MQL5 )
rm -rf "$TMP"

echo "built $OUT"
echo "  $(unzip -l "$OUT" | grep -c '\.ex5') compiled programs, build $BUILD"
