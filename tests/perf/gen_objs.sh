#!/bin/bash
# Regenerate yosys_objs.txt for current GIT_REV.
set -e
cd "$(dirname "$0")/../.."
mkdir -p benchmark-results
OBJ_LIST=benchmark-results/yosys_objs.txt
GIT_REV=$(git rev-parse --short=9 HEAD)
make -p yosys.exe 2>/dev/null | grep -E '^OBJS[[:space:]]*=' | sed \
    -e 's/^OBJS[[:space:]]*=[[:space:]]*//' \
    -e "s|\$(GIT_REV)|$GIT_REV|g" \
    -e 's|$(OPT_CLEAN_OBJS)|passes/opt/opt_clean/cells_all.o passes/opt/opt_clean/cells_temp.o passes/opt/opt_clean/wires.o passes/opt/opt_clean/inits.o passes/opt/opt_clean/opt_clean.o|g' > $OBJ_LIST
wc -w $OBJ_LIST
