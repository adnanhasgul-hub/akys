#!/usr/bin/env python3
"""Summarize complete isolated benchmark runs; no numeric score conversion."""
import gzip
import json
import pathlib
import sys
from collections import Counter
from fractions import Fraction

root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
fixtures = [(6, 'mixed'), (10, 'ratio'), (15, 'surplus'), (20, 'rank')]
strategies = ('deadends', 'combined', 'twophase', 'bounded')
runs, snapshots = [], {}
revision = None
for size, variant in fixtures:
    for strategy in strategies:
        for rep in (1, 2, 3):
            path = root / f'{size}-{variant}-{strategy}-{rep}.json'
            item = json.loads(path.read_text())
            if revision is None:
                revision = item['sourceRevision']
            elif item['sourceRevision'] != revision:
                raise ValueError(f'source revision mismatch: {path}')
            snapshot = item.pop('snapshot')
            key = f'{size}-{variant}'
            if key in snapshots and snapshots[key] != snapshot:
                raise ValueError(f'snapshot mismatch: {path}')
            snapshots[key] = snapshot
            item['snapshotKey'] = key
            runs.append(item)

def find(size, strategy, rep):
    return next(x for x in runs if x['people'] == size and x['strategy'] == strategy and x['repeat'] == rep)

def value_range(values, fmt=str):
    vals = [v for v in values if v is not None]
    return 'none' if not vals else f'{fmt(min(vals))}–{fmt(max(vals))}'

def checkpoint(item, index):
    marks = item['marks']
    if len(marks) > index:
        return marks[index]
    if len(marks) == 1 and marks[0]['status'] in ('optimal', 'infeasible'):
        return marks[0]  # Exact terminal result; not a later observation.
    raise ValueError(f'Missing checkpoint: {item["snapshotKey"]}/{item["strategy"]}')

lines = ['\n## 30/120-second results', '', '| Doctors / fixture | Strategy | First ms range | 30s filled | 120s filled | 120s nodes | Prefix prunes | Improvements | Peak RSS MiB | Status |', '|---|---|---|---|---|---|---|---|---|---|']
for size, variant in fixtures:
    for strategy in strategies:
        items = [find(size, strategy, i) for i in (1, 2, 3)]
        last = [checkpoint(x, 1) for x in items]
        first = [x['firstMicros'] / 1000 if x['firstMicros'] is not None else None for x in items]
        pruned = [x['mandatoryPruned'] + x['feasibilityPruned'] + x['clinicalPruned'] for x in last]
        rss = [x['peakRssBytes'] / (1024 * 1024) if x['peakRssBytes'] is not None else None for x in last]
        lines.append(f"| {size} / {variant} | {strategy} | {value_range(first, lambda x: f'{x:.2f}')} | {value_range([checkpoint(x, 0)['optionalFilled'] for x in items])} | {value_range([x['optionalFilled'] for x in last])} | {value_range([x['visitedNodes'] for x in last])} | {value_range(pruned)} | {value_range([x['improvements'] for x in last])} | {value_range(rss, lambda x: f'{x:.1f}')} | {','.join(sorted(set(x['status'] for x in last)))} |")
lines += ['\n## Exact quality vectors, first repetition', '', '| Doctors | Strategy | First | 30s | 120s |', '|---:|---|---|---|---|']
for size, _ in fixtures:
    for strategy in strategies:
        item = find(size, strategy, 1)
        def vector(value):
            return 'none' if value is None else '`' + ','.join(value) + '`'
        lines.append(f"| {size} | {strategy} | {vector(item['firstQuality'])} | {vector(checkpoint(item, 0)['quality'])} | {vector(checkpoint(item, 1)['quality'])} |")
lines += ['\n## 120s paired comparisons', '', '| Doctors | bounded vs deadends | bounded vs combined | bounded vs twophase |', '|---:|---|---|---|']
for size, _ in fixtures:
    comparisons = []
    for other in ('deadends', 'combined', 'twophase'):
        counts = Counter()
        for rep in (1, 2, 3):
            a = checkpoint(find(size, 'bounded', rep), 1)['quality']
            b = checkpoint(find(size, other, rep), 1)['quality']
            if a is None or b is None:
                counts['missing'] += 1
            else:
                aa, bb = list(map(Fraction, a)), list(map(Fraction, b))
                counts['better' if aa < bb else 'equal' if aa == bb else 'worse'] += 1
        comparisons.append(', '.join(f'{counts[k]} {k}' for k in ('better', 'equal', 'worse', 'missing') if counts[k]))
    lines.append(f"| {size} | {' | '.join(comparisons)} |")
output.mkdir(parents=True, exist_ok=True)
with (output / 'summary.md').open('w') as f:
    f.write('\n'.join(lines) + '\n')
with (output / 'traces.json.gz').open('wb') as raw:
    with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0, compresslevel=9) as f:
        f.write(json.dumps({'sourceRevision': revision, 'snapshots': snapshots, 'runs': runs}, separators=(',', ':')).encode())
print(f'{len(runs)} runs, {len(snapshots)} snapshots')
