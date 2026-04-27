import json
import glob
import os
import sys

pattern = sys.argv[1] if len(sys.argv) > 1 else 'benchmark-results/sigspec-*-synthetic-*.json'

for f in sorted(glob.glob(pattern)):
    d = json.load(open(f))
    cases = {}
    for case, info in d['results'].items():
        runs = sorted(r['measured_wall_seconds'] for r in info['runs'])
        cases[case] = runs[len(runs) // 2]
    name = os.path.basename(f).replace('.json', '')
    parts = []
    for k in ['many_equiv_cells_30000', 'many_equiv_cells_60000', 'wide_opt_chain_3000', 'simple_synth_noabc', 'opt_share_large_pmux_cat']:
        if k in cases:
            parts.append('%s=%.3f' % (k[:24], cases[k]))
    print('%-55s %s' % (name, ' '.join(parts)))
