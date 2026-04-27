#!/bin/bash
# Usage: ./run_loop.sh <label>
# Builds microbench + yosys at current source state, then runs both benchmarks
# and saves results as benchmark-results/<label>-* files (gitignored scratch).
set -e
LABEL=${1:-test}
DATE=$(date +%Y-%m-%d)
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

mkdir -p benchmark-results
OBJ_LIST=benchmark-results/yosys_objs.txt

echo "[$LABEL] building microbench..."
x86_64-w64-mingw32-g++ -O3 -DNDEBUG -std=c++17 -I. \
    tests/perf/hashlib_microbench.cc \
    -o benchmark-results/hashlib_microbench.exe

echo "[$LABEL] running microbench 5x (median)..."
python - "$LABEL" "$DATE" <<'PYEOF'
import json, os, statistics, subprocess, sys
label, date = sys.argv[1], sys.argv[2]
runs = []
for _ in range(5):
    out = subprocess.check_output([os.path.abspath("benchmark-results/hashlib_microbench.exe")], text=True)
    runs.append(json.loads(out))
keys = ["dict_int_lookup_ns_per_op", "pool_int_insert_ns_per_op",
        "pool_int_count_ns_per_op", "pool_int_erase_ns_per_op"]
agg = {k: statistics.median([r[k] for r in runs]) for k in keys}
agg["keys"] = runs[0]["keys"]
agg["probes"] = runs[0]["probes"]
agg["samples"] = len(runs)
out_path = f"benchmark-results/hashlib-microbench-{label}-{date}.json"
with open(out_path, "w") as f:
    json.dump(agg, f, indent=2, sort_keys=True)
print(f"  wrote {out_path}")
for k in keys:
    print(f"  {k}: {agg[k]:.3f}")
PYEOF

echo "[$LABEL] compiling .o files (make may report link error; that's expected)..."
# Touch hashlib.h to ensure all dependents rebuild
touch kernel/hashlib.h
# Force-clean any .o files that depend on hashlib.h but might have been
# skipped by previous failed make runs.
find passes kernel frontends backends techlibs libs -name '*.o' \
    \! -newer kernel/hashlib.h -print -exec rm {} \; 2>&1 | grep -v "^libs/\|version_" | head -20 || true
# Run make; the link step will fail because Windows cmd line is too long.
make -j6 yosys.exe 2>&1 | tail -3 || true

echo "[$LABEL] linking yosys.exe via response file..."
# Refresh OBJS list with current git rev (commit hash changes between iterations)
make -p yosys.exe 2>/dev/null | grep -E "^OBJS\s*=" | sed \
    -e 's/^OBJS\s*=\s*//' \
    -e "s/\\\$(GIT_REV)/$(git rev-parse --short=9 HEAD)/g" \
    -e 's/\$(OPT_CLEAN_OBJS)/passes\/opt\/opt_clean\/cells_all.o passes\/opt\/opt_clean\/cells_temp.o passes\/opt\/opt_clean\/wires.o passes\/opt\/opt_clean\/inits.o passes\/opt\/opt_clean\/opt_clean.o/g' > $OBJ_LIST
RSPFILE=$(mktemp /tmp/yosys-link-XXXXXX.rsp)
tr ' ' '\n' < $OBJ_LIST | grep -v '^$' > "$RSPFILE"
x86_64-w64-mingw32-g++ -o yosys.exe \
    -Wl,--export-all-symbols -Wl,--out-implib,libyosys_exe.a \
    -s "@$RSPFILE" -lstdc++ -lm -lpthread
rm -f "$RSPFILE"
./yosys.exe -V | head -1

echo "[$LABEL] running default-case yosys benchmarks..."
python tests/tools/benchmark_yosys.py \
    --yosys ./yosys.exe --repeat 5 --warmup 1 --keep-logs \
    --output benchmark-results/${LABEL}-baseline-${DATE}.json 2>&1 | tail -15

echo "[$LABEL] running synthetic-case yosys benchmarks..."
python tests/tools/benchmark_yosys.py \
    --yosys ./yosys.exe --repeat 3 --warmup 1 --keep-logs \
    --case many_equiv_cells_30000=tests/perf/many_equiv_cells_30000.ys \
    --case many_equiv_cells_60000=tests/perf/many_equiv_cells_60000.ys \
    --case wide_opt_chain_3000=tests/perf/wide_opt_chain_3000.ys \
    --output benchmark-results/${LABEL}-synthetic-${DATE}.json 2>&1 | tail -15

echo "[$LABEL] done."
