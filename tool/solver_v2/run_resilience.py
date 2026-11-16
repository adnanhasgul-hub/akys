#!/usr/bin/env python3
"""Sequential, interruption-safe Stage 1.6 measurements. No concurrent VMs."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
if subprocess.check_output(['git', 'status', '--porcelain', '-uall'], text=True).strip():
    raise SystemExit('Commit measurement source before running')
for case in ['6-open', '10-open', '15-open', '20-open', '6-tight', '10-tight',
             '15-tight', '20-tight', '6-transition', '10-capacity', '15-blocked']:
    # Blocked final day is a short unknown/proof check, not a clinical speed claim.
    seconds = 1 if case == '15-blocked' else 120
    for strategy in ['deadends', 'combined', 'twophase', 'bounded']:
        path = root / f'{case}-{strategy}.json'
        if path.exists():
            record = json.loads(path.read_text())
            assert record['sourceRevision'] == revision
            assert (record['case'], record['strategy'], record['budgetSeconds']) == (case, strategy, seconds)
            assert record['marks'][-1]['seconds'] == seconds or record['marks'][-1]['status'] in ('optimal', 'infeasible')
            print('reused', path.name, flush=True)
            continue
        # A killed run leaves only .partial; finished atomic outputs are never replaced.
        temporary = path.with_suffix('.partial')
        with temporary.open('w') as handle:
            subprocess.run(['dart', '--packages=.dart_tool/package_config.json',
                            'tool/solver_v2/resilience_compare.dart', case, strategy, str(seconds)],
                           stdout=handle, check=True, timeout=seconds + 60)
            handle.flush()
            os.fsync(handle.fileno())
        record = json.loads(temporary.read_text())
        assert record['sourceRevision'] == revision
        os.replace(temporary, path)
        print('completed', path.name, record['marks'][-1]['status'], flush=True)
