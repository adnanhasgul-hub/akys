#!/usr/bin/env python3
"""Reproduce exact paired tables from Stage 1.7A measurements."""
import json,pathlib,gzip,sys
from fractions import Fraction
if len(sys.argv)!=3: raise SystemExit('usage: summarize_forward.py RESULTS_DIR OUTPUT_DIR')
root=pathlib.Path(sys.argv[1])
out=pathlib.Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
runs=[json.loads(p.read_text()) for p in sorted(root.glob('*.json'))]
assert len(runs)==24,len(runs)
assert len({r['sourceRevision'] for r in runs})==1
snaps={}
for r in runs:
 key=r['case']
 if key in snaps:assert snaps[key]==r['snapshot']
 snaps[key]=r['snapshot']
 for m in r['marks']:
  assert m['quality'] is None or len(m['quality'])==19
  assert not m['optimalityProven'] or m['status']=='optimal'
  if m['quality'] is not None:
   assert m['independentlyChecked']>0
   assert list(map(Fraction,m['quality']))<=list(map(Fraction,r['firstQuality']))
  if not r['forwardChecking']:assert m['forwardChecks']==0
  if key=='15-blocked':
   assert m['assignments'] is None
   assert m['status']==('infeasible' if r['forwardChecking'] else 'timeoutWithoutSolution')
   assert m['restrictedVerdict']==('provenInfeasible' if r['forwardChecking'] else 'pending')

def ms(x):return '—' if x is None else f'{x/1000:.3f}'
def q(x):return '—' if x is None else '`'+','.join(x)+'`'
def mode(r):return 'on' if r['forwardChecking'] else 'off'
lines=['## Matched measurements','', '|Case|Strategy|Budget s|Check|First ms|Proof ms|DFS A+B|Forward rejects (root)|Check wall ms|Process CPU s|Peak RSS MiB|Final status|','|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|']
for r in runs:
 m=r['marks'][-1];cpu='—' if m['cpuTicksFromStart'] is None else f"{m['cpuTicksFromStart']/int(r['cpuTicksPerSecond']):.2f}"
 lines.append(f"|{r['case']}|{r['strategy']}|{r['budgetSeconds']}|{mode(r)}|{ms(r['firstMicros'])}|{ms(m['proofMicros'])}|{m['visitedNodes']}|{m['forwardPruned']} ({m['forwardRootPruned']})|{m['forwardWallTicks']*1000/m['stopwatchFrequency']:.3f}|{cpu}|{m['peakRssBytes']/1048576:.1f}|{m['status']}|")
lines+=['','## Exact clinical vectors and OPTIONAL coverage','', '|Case|Strategy|Budget|Check|First quality|30s or early terminal/1s diagnostic|120s if reached|OPTIONAL first checkpoint → last|','|---|---|---:|---|---|---|---|---|']
for r in runs:
 marks=r['marks'];lines.append(f"|{r['case']}|{r['strategy']}|{r['budgetSeconds']}|{mode(r)}|{q(r['firstQuality'])}|{q(marks[0]['quality'])}|{q(marks[1]['quality']) if len(marks)>1 else 'not separately measured'}|{marks[0]['optionalFilled']} → {marks[-1]['optionalFilled']}|")
lines+=['','## Normal-clinic on/off comparisons','', '|Case|First ms off → on|30s quality on vs off|120s quality on vs off|Nodes off → on|Check share of elapsed 120s|','|---|---|---|---|---|---|']
for n in (6,10,15,20):
 group=[r for r in runs if r['case']==f'{n}-open'];off=next(r for r in group if not r['forwardChecking']);on=next(r for r in group if r['forwardChecking'])
 outcomes=[]
 for i in (0,1):
  a=list(map(Fraction,on['marks'][i]['quality']));b=list(map(Fraction,off['marks'][i]['quality']));outcomes.append('better' if a<b else 'equal' if a==b else 'worse')
 m=on['marks'][-1];share=m['forwardWallTicks']/m['stopwatchFrequency']/(m['observedMicros']/1e6)*100
 lines.append(f"|{n}-open|{ms(off['firstMicros'])} → {ms(on['firstMicros'])}|{outcomes[0]}|{outcomes[1]}|{off['marks'][-1]['visitedNodes']} → {m['visitedNodes']}|{share:.2f}%|")
(out/'results.md').write_text('\n'.join(lines)+'\n')
with (out/'traces.json.gz').open('wb') as f:
 with gzip.GzipFile(fileobj=f,filename='',mtime=0,mode='wb') as z:z.write(json.dumps({'runs':runs},separators=(',',':')).encode())
print('24 runs validated; tables and raw archive ready')
