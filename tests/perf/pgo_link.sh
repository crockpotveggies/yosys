#!/bin/bash
# PGO-aware variant of link_yosys.sh. Pass extra g++ flags as $1.
set -e
cd "$(dirname "$0")/../.."
OBJ_LIST=benchmark-results/yosys_objs.txt
EXTRA="$1"
RSPFILE=$(mktemp /tmp/yosys-link-XXXXXX.rsp)
tr ' ' '\n' < $OBJ_LIST | grep -v '^$' > "$RSPFILE"
echo "Linking with extra flags: $EXTRA"
x86_64-w64-mingw32-g++ -o yosys.exe \
    -Wl,--export-all-symbols -Wl,--out-implib,libyosys_exe.a \
    $EXTRA \
    "@$RSPFILE" -lstdc++ -lm -lpthread -lgcov
rm -f "$RSPFILE"
./yosys.exe -V | head -1
