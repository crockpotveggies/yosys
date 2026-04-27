#!/bin/bash
# Run benchmarks once to populate .gcda PGO training data.
set -e
cd "$(dirname "$0")/../.."

# Each invocation generates .gcda files alongside the .o files.
# Pass `-warmup 0 -repeat 2` so we get coverage of all hot paths
# without burning extra cycles. Two iters = stable training.

python tests/tools/benchmark_yosys.py \
    --yosys ./yosys.exe \
    --repeat 2 --warmup 0 \
    --case many_equiv_cells_30000=tests/perf/many_equiv_cells_30000.ys \
    --case many_equiv_cells_60000=tests/perf/many_equiv_cells_60000.ys \
    --case wide_opt_chain_3000=tests/perf/wide_opt_chain_3000.ys \
    --case picorv32_synth=tests/perf/picorv32_synth.ys \
    --output /tmp/pgo-training.json 2>&1 | tail -3

echo "PGO training done. .gcda files written next to .o files."
find . -name "*.gcda" 2>/dev/null | wc -l | xargs echo "gcda count:"
