#!/usr/bin/env python3
"""One VM at a time. Atomic results and source-checked resume, Stage 1.7A."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
if subprocess.check_output(['git', 'status', '--porcelain', '-uall'], text=True).strip():
    raise SystemExit('Commit measurement source first')
cells = [('15-blocked', strategy, mode, seconds)
         for seconds in [1, 120]
         for strategy in ['deadends', 'combined', 'twophase', 'bounded']
         for mode in ['off', 'on']]
cells += [(f'{n}-open', 'bounded', mode, 120)
          for n in [6, 10, 15, 20] for mode in ['off', 'on']]
for case, strategy, mode, seconds in cells:
    path = root / f'{case}-{strategy}-{mode}-{seconds}.json'
    def valid(record):
        assert record['sourceRevision'] == revision
        assert (record['case'], record['strategy'], record['forwardChecking'], record['budgetSeconds']) == (case, strategy, mode == 'on', seconds)
        assert record['marks'][-1]['seconds'] == seconds or record['marks'][-1]['status'] in ('optimal', 'infeasible')
    if path.exists():
        valid(json.loads(path.read_text()))
        print('reused', path.name, flush=True)
        continue
    temp = path.with_suffix('.partial')
    with temp.open('w') as f:
        subprocess.run(['dart', '--packages=.dart_tool/package_config.json',
                        'tool/solver_v2/forward_compare.dart', case, strategy,
                        mode, str(seconds)], stdout=f, check=True, timeout=seconds+60)
        f.flush()
        os.fsync(f.fileno())
    record = json.loads(temp.read_text())
    valid(record)
    os.replace(temp, path)
    print('completed', path.name, record['marks'][-1]['status'], flush=True)
