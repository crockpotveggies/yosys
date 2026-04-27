# yosys perf optimization work — summary

Branch: `crockpot/optimization-v1` (off `main`)
Period: 2026-04-24 → 2026-04-26

## Headline result

**~1.85× geomean speedup over original `main`** across the four primary benchmarks.

| Benchmark | Original `main` | Current branch | Speedup |
|---|---|---|---|
| many_equiv_cells_30000 (mec30k) | 3.222s | ~2.00s | 1.61× |
| many_equiv_cells_60000 (mec60k) | 6.242s | ~4.29s | 1.45× |
| wide_opt_chain_3000 (woc3k) | 3.073s | ~1.50s | 2.05× |
| picorv32_x4 | ~3.95s (loop10) | ~2.04s | 1.94× |

Numbers are wall-clock medians from `tests/tools/benchmark_yosys.py` (5 reps default, 3 reps synthetic, 1 warmup).

## What changed (chronological, by area)

### kernel/hashlib.h — the foundation (loops 1-10, codex + follow-up)
- Cached `entries.data()` / `hashtable.data()` in `do_rehash` and `do_erase` to defeat the compiler's pessimistic alias assumptions.
- Killed unnecessary asserts in hot lookup paths.
- Strategic prefetch on chain walks.
- `fastmod` for bucket compression with `swap()`/`clear()` propagation of the precomputed magic. (Caught by canary tests when first attempt forgot the magic propagation.)

### kernel/rtlil.* — SigSpec hot paths
- Read-only iteration that doesn't speculatively unpack the chunk vector (`SigSpec::read_at`).
- Cheap pre-check in `try_repack` to skip the O(N) walk on guaranteed misses.
- Two rvalue-ref ctors that were silently copying instead of moving.
- `swap()`/`clear()` must propagate the fastmod magic (correctness, not perf).

### Pass-level early-bail audit (multiple commits)
The biggest single ROI category. Many passes do unconditional O(N) constructor work (build SigMap, sigusers, mux_drivers, ConstEval seed) before discovering they have nothing to do.
- `proc_dlatch / proc_dff / proc_arst / proc_init / proc_prune / proc_rom / proc_memwr`: skip when no processes selected (proc_dlatch alone wasted ~400ms/call on FF-free designs).
- `opt_dff`: skip bitusers/bit2mux build when no muxes present.
- `opt_muxtree / opt_reduce`: skip worker construction when no target cells.
- `opt_share`: skip SigMap+bit_users walk when no supported cells.
- `opt`: early-exit convergence loop when last iteration's heavy passes (share+dff) reported no work — saves ~500ms-1s of cleanup work in the final iteration. **+28% on wide_opt_chain_3000.**

### opt_expr internals (5 loops, 3 commits)
- Trim per-call setup in `replace_const_cells`: filter polarity-inv walk to FF/SR/dlatch/mem cells only; combine the two TopoSort-build walks into one; cache TopoSort indices in a side vector.
- Dedupe consecutive same-producer edges in TopoSort build.
- Per-execute() cache of `TopoSort.sorted` + `invert_map`, validated by the per-Module generation counter (see below). Skip the entire body when validated AND last call did nothing.
- **Cumulative: -9% picorv32_x4, -5% mec30k, -8% woc3k.**

### Per-Module generation counter (commit `b2a18dc8d`)
Foundational change. Added `uint64_t generation` to `RTLIL::Module`, drawn from a process-wide monotonic counter. Bumped on every structural mutation (`Module::add/remove/connect/new_connections`, `Cell::setPort/unsetPort`). Pointer reuse after `design -reset` is safe because each new Module gets a fresh global generation.

This unlocked safe cross-execute() no-op caches in passes that were previously blocked by Module pointer reuse.

### Generation-counter no-op caches retrofitted to:
- `opt_dff`, `opt_share` (`dc2a8b534`)
- `opt_muxtree`, `opt_reduce`, `opt_clean`, `clean` (`c3fe2d359`)
- `wreduce`, `peepopt` (`fab4ba6bb`)
- `alumacc` with cell-type early-bail (`1ac6071c0`)

Pattern: `static std::map<RTLIL::Module*, {generation, last_did_something}>` at top of `execute()`. Skip per-module work when generation matches and last call did nothing.

### AST genrtlil helpers (commit `8e1ef04d5`, this session)
- Hoisted `loc_string()` in the four per-cell helpers (`uniop2rtlil`, `widthExtend`, `binop2rtlil`, `mux2rtlil`) so each call computes the source-location string once and reuses it for both the cell and its output wire.
- Added `set_src_attr(AttrObject*, const std::string&)` overload.
- Removed wasted stringstream construction in `RTLIL::encode_filename`'s ASCII fast path.
- **mec60k grtl_main: 728ms → ~595–687ms (~5–18%, run-to-run noisy). mec60k total ~3-4%. picorv32_x4 unchanged.**

## Learnings

### What worked
1. **Early-bail audits are the highest-ROI optimization left.** Many passes do O(N) constructor work before discovering they have nothing to do. A 5-line `if (...) continue;` at the top of `execute()` can deliver 30%+ on the right input. Always check whether a pass has a worklist that's empty before building indices.
2. **Per-Module generation counter unlocks safe caches.** Once you can prove the module hasn't changed, you can cache anything derived from it across calls.
3. **Compiler is conservative around opaque calls.** Caching `data()` pointers across calls to user-defined comparators / hash functions gave ~7% in hashlib because the compiler wouldn't prove the pointer was loop-invariant.
4. **Profile first; intuition is wrong.** The user's hypothesis that opt_merge/opt_clean dominated mec was wrong — `proc` was the bottleneck. Per-Module timing instrumentation around `simplify` and the three `genRTLIL` phases caught this in one loop.
5. **Canary tests catch fastmod-style bugs immediately.** `tests/various/{wreduce,wreduce2,peepopt,muxpack}.ys` are the four tests that exercise hashlib bucket assignment edge cases.

### What didn't work (do NOT retry without a different angle)
1. **Lemire multiply-shift bucket compression.** Microbenched as ~17% win, but changed bucket assignment which broke an order-fragile fixed-point loop in `opt -fast` (600k+ iterations no convergence).
2. **`udata_hash` cached in `entry_t`.** +4 bytes per entry hurt cache more than the rehash savings helped. Also caused intermittent `pool<>` assert failures from default-ctor leaving the field uninitialized.
3. **Speculative load of `entries[index].next` before `ops.cmp`.** −35% on `dict_lookup` — chains are too short at load factor 0.5.
4. **`dict.reserve(N)` in mass-instantiated object ctors** (e.g. `Cell::parameters`). Capacity reservation costs memory per object even when most never reach N entries; cache locality dominates. Reserve only for one-off large dicts.
5. **AstNode arena allocator (free-list AND slab).** Mixed results: read-bound benchmarks +5–9%, cell-heavy benchmarks −6–13%. Arena pollutes cache during opt passes. Even with a clean migration scheme, `AstModule::ast` survives across `design -reset`/`design -copy` boundaries — fundamental incompatibility with yosys design-management semantics. Would require multi-day raw-pointer ownership refactor (~200 sites) for marginal win.
6. **AST::process per-module parallelism.** Blocked by explicit `log_assert(!Multithreading::active())` in `IdString::insert / get_reference / put_reference / new_autoidx_with_prefix`. Yosys's threading model is "parallel analysis, serial commit"; AST processing creates IdStrings inline and can't fit that pattern. Multi-week architectural rewrite to fix; out of scope for perf work.
7. **opt_share parallelism.** Researched and feasible, but expected gain is only 2-3% on picorv32_x4 — below the threshold where ~150 LOC of concurrent code + new tests + cross-platform threading variability is justified.
8. **PGO build.** +13–21% slower across all benchmarks, including trained ones. Training corpus too narrow + instrumentation overhead distorts relative counters. Don't retry without a much wider training corpus + verifying gcov outputs per .o file.
9. **SigMap hoist out of `replace_const_cells`.** Showed -4% on picorv32_x4 but broke `tests/opt/opt_expr.ys` because `opt_expr.cc` has many bare `module->connect()` calls that DON'T have a matching `assign_map.add()`. Original code masked this by rebuilding SigMap each call. Auditing every connect site is substantial work, easy to miss one.
10. **Hash-tag in `entry_t`** (1-byte filter for chain walks). Broke ~12 tests in `tests/various` deterministically (`std::out_of_range` from `dict::at()`) but debug instrumentation never caught the divergence. Hypothesis: yosys has a latent invariant violation (cmp-equal keys with different `ops.hash`) that the tag check exposes.

### Methodology lessons
- **Always rebuild stale .o files after RTLIL layout changes.** When changing `RTLIL::Module`'s memory layout, the .o files in `passes/opt/opt_clean/`, `libs/*`, etc. are NOT rebuilt by `make -j6` because their .d dependency files don't track `kernel/rtlil.h`. The resulting binary has ABI mismatch and SEGVs in unrelated code. Workflow: `find . -name "*.o" ! -newer kernel/rtlil.h | xargs rm -f` then rebuild.
- **5-rep run-to-run variance is significant on Windows.** Apparent 1-4% wins frequently disappear with 10-rep verification. Take medians, run 5+ samples for any decision near the noise floor.
- **Microbench wins ≠ end-to-end wins.** A 17% microbench win for Lemire bucket compression hid the order-fragility bug; the only reliable signal is full benchmark + canary test suite.

## Recommended areas for further optimization

Listed by ROI / effort. None of these are obviously worth the effort given the current 1.85× already achieved.

### Low effort / low reward
- **Cache `encode_filename` per filename pointer.** Currently called 60006× on mec60k. ASCII fast path is cheap but cache would save ~3-6ms.
- **AST_MEMRD / AST_FCALL paired set_src_attr hoist** (lines ~2049/2052 and ~2361/2372 in `frontends/ast/genrtlil.cc`). Same pattern as the helpers that landed in `8e1ef04d5`. Only material if a memory-heavy or function-heavy benchmark is added.

### Medium effort / unknown reward
- **Profile recursive `simplify()` for AST_ASSIGN.** The largest remaining hot spot on mec60k (~780ms). The function is 6096 lines and order-sensitive. Instrumentation already shows `simp(0 iters)` returns false on first call but does 780ms of internal work — there's a hidden inner convergence loop that may be amenable to early-bail or memoization.
- **opt_clean integration with the generation counter** (currently uses ThreadPool but not the gen-counter cache). The two systems should compose; needs care around the `module->connections_.clear()` per-iter destructive operation.

### High effort / high risk / multi-day refactor
- **AstNode arena allocator with raw-pointer ownership refactor.** The only path that cleanly bulk-frees AST memory at end of frontend. ~200 unique_ptr sites, expected ~3% win on read-bound benchmarks. Marginal.
- **Per-design generation counter.** Would let static per-Module caches survive `design -reset` safely (currently Module pointers get reused, killing caches). Several blocked optimizations would unlock.
- **Worklist-based opt_share/opt_dff.** Substantial rewrite of each pass. Only re-process cells touched since last call.
- **Cross-pass shared SigMap maintained at `opt -full` level.** Requires auditing every `module->connect()` site (~50+) and adding incremental SigMap updates. High effort, no clear win-size estimate.
- **Make `IdString::insert/get_reference/put_reference` thread-safe + atomic `autoidx`.** Would unlock per-module AST parallelism (~12 modules in picorv32_x4 × ~50ms each = ~400ms theoretical). Yosys-wide threading-model rewrite, breaks every plugin assuming the single-thread invariant.

## What's NOT a recommended area
- More hashlib micro-optimizations. The data structure has been heavily tuned; further changes risk the order-fragility class of bug we already hit.
- More PGO attempts without a fundamentally different training corpus.
- Adding more `dict.reserve()` calls.
- Anything that changes hashtable iteration order.

## Files of interest

| File | Why |
|---|---|
| `benchmark-results/SUMMARY-2026-04-24.md` | hashlib loops 6-10 detailed numbers |
| `benchmark-results/run_loop.sh` | end-to-end build + microbench + benchmark workflow |
| `benchmark-results/link_yosys.sh` | response-file linker (Windows command-line too long for 330 .o) |
| `benchmark-results/gen_objs.sh` | regenerate `yosys_objs.txt` with current GIT_REV |
| `benchmark-results/generated/*.ys` | synthetic + picorv32 benchmark scripts |
| `kernel/rtlil.h` | Module generation counter; SigSpec hot paths; encode_filename |
| `kernel/hashlib.h` | dict/pool with cached data ptrs, fastmod, prefetch |
| `frontends/ast/genrtlil.cc` | per-cell helpers; `set_src_attr` hoist |
| `passes/opt/opt_expr.cc` | per-execute() cache + generation-counter validation |
| `passes/opt/{opt_dff,opt_share,opt_muxtree,opt_reduce,wreduce,peepopt}.cc` | generation-counter no-op caches |
| `passes/proc/proc_*.cc` | early-bail when no processes |
