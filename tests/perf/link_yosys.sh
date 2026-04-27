#!/bin/bash
# Link yosys.exe directly using a response file to avoid Windows shell line-length issues.
# Assumes all .o files are already built and up-to-date.
set -e
cd "$(dirname "$0")/../.."
RSPFILE=$(mktemp /tmp/yosys-link-XXXXXX.rsp)
cat benchmark-results/yosys_objs.txt | tr ' ' '\n' | grep -v '^$' > "$RSPFILE"
echo "Linking $(wc -l < "$RSPFILE") objects via $RSPFILE..."
x86_64-w64-mingw32-g++ -o yosys.exe \
    -Wl,--export-all-symbols -Wl,--out-implib,libyosys_exe.a \
    -s "@$RSPFILE" -lstdc++ -lm -lpthread
RC=$?
rm -f "$RSPFILE"
exit $RC
