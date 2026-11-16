#!/usr/bin/env python3
"""Rebuild Stage 1.6 tables from immutable measured outputs; no solver execution."""
import json,gzip,pathlib,collections,datetime,sys
from fractions import Fraction
if len(sys.argv)!=4: raise SystemExit('usage: summarize_resilience.py MAIN_RESULTS EXTENDED_RESULTS OUTPUT')
root=pathlib.Path(sys.argv[1])
extended=pathlib.Path(sys.argv[2])
out=pathlib.Path(sys.argv[3]);out.mkdir(parents=True,exist_ok=True)
runs=[json.loads(p.read_text()) for p in sorted(root.glob('*.json'))]
assert len(runs)==44, len(runs)
extra=[json.loads(p.read_text()) for p in sorted(extended.glob('*.json'))]
assert len(extra)==4
assert {r['strategy'] for r in extra}=={'deadends','combined','twophase','bounded'}
assert all(r['case']=='15-blocked' and r['budgetSeconds']==120 for r in extra)
runs+=extra
assert len({(r['case'],r['strategy'],r['budgetSeconds']) for r in runs})==48
assert len({r['sourceRevision'] for r in runs})==1
snapshots={}
for r in runs:
 s=r['snapshot'];key=r['case']
 if key in snapshots: assert snapshots[key]==s
 snapshots[key]=s
 for m in r['marks']:
  assert not m['optimalityProven'] or m['status']=='optimal'
  assert m['quality'] is None or len(m['quality'])==19
  if m['assignments'] is not None: assert m['independentlyChecked']>0
  if m['quality'] and int(m['quality'][0])>0: assert m['restrictedVerdict']=='provenInfeasible'
  if m['quality'] and r['firstQuality']: assert list(map(Fraction,m['quality']))<=list(map(Fraction,r['firstQuality']))

def q(x): return '—' if x is None else '`'+','.join(x)+'`'
lines=['## Final matrix', '', '|Case|Senior / junior|Required / optional|Must / cannot entries|','|---|---|---|---|']
for k,s in snapshots.items():
 gs=collections.Counter(d['group'] for d in s['doctors']);rs=collections.Counter(s['slotRequirements'])
 lines.append(f"|{k}|{gs['senior']} / {gs['junior']}|{rs['required']} / {rs['optional']}|{sum(len(d['must']) for d in s['doctors'])} / {sum(len(d['unavailable']) for d in s['doctors'])}|")
lines+=['','## Performance (one repetition per cell)', '', '|Case / budget|Strategy|First ms|Final elapsed s|Nodes|Pruned prefixes|Optional filled|Improvements|Peak RSS MiB|Status / restricted verdict|','|---|---|---:|---:|---:|---:|---:|---:|---:|---|']
for r in runs:
 m=r['marks'][-1];first='—' if r['firstMicros'] is None else f"{r['firstMicros']/1000:.2f}"
 lines.append(f"|{r['case']} / {r['budgetSeconds']}s|{r['strategy']}|{first}|{m['observedMicros']/1e6:.3f}|{m['visitedNodes']}|{m['mandatoryPruned']+m['feasibilityPruned']+m['clinicalPruned']}|{m['optionalFilled']}|{m['improvements']}|{m['peakRssBytes']/1048576:.1f}|{m['status']} / {m['restrictedVerdict']}|")
lines+=['','## Exact quality vectors', '', 'A single early terminal mark denotes a proof at its actual elapsed time, not a separate 30/120-second measurement.', '', '|Case|Strategy|First|30s or early terminal|120s (if still running)|','|---|---|---|---|---|']
for r in runs:
 lines.append(f"|{r['case']} / {r['budgetSeconds']}s|{r['strategy']}|{q(r['firstQuality'])}|{q(r['marks'][0]['quality'])}|{q(r['marks'][1]['quality']) if len(r['marks'])>1 else 'terminal or 1s diagnostic; not measured'}|")
lines+=['','## Within-snapshot lexicographic winners', '', '|Case|30 seconds|120 seconds|','|---|---|---|']
for key in [f'{n}-open' for n in (6,10,15,20)]:
 group=[r for r in runs if r['case']==key];wins=[]
 for idx in (0,1):
  best=min(tuple(map(Fraction,r['marks'][idx]['quality'])) for r in group if r['marks'][idx]['quality'])
  wins.append(', '.join(r['strategy'] for r in group if tuple(map(Fraction,r['marks'][idx]['quality']))==best))
 lines.append('|'+key+'|'+'|'.join(wins)+'|')
(out/'results.md').write_text('\n'.join(lines)+'\n')
# Independent transparent descriptive statistics from checkpoint assignments.
stats=[]
for r in runs:
 s=r['snapshot'];m=r['marks'][-1];assign=m['assignments']
 if assign is None: continue
 start=datetime.datetime.fromisoformat(s['startDate'].replace('Z','+00:00'))
 counts=[0]*len(s['doctors']);points=counts.copy();weekday=[[0]*7 for _ in counts];slot=0
 for day,size in enumerate(s['slotsPerDay']):
  score=s['dayDifficulties'][day];v=max(score['weekdayScore'],score.get('holidayScore') or 0)
  for _ in range(size):
   d=assign[slot];slot+=1
   if d<0: continue
   counts[d]+=1;points[d]+=v;weekday[d][(start+datetime.timedelta(days=day)).weekday()]+=1
 stats.append({'case':r['case'],'strategy':r['strategy'],'doctors':[{'id':d['id'],'group':d['group'],'level':d.get('seniorityLevel'),'count':counts[i],'cap':d['maxDuties'],'load':str(Fraction(counts[i],d['maxDuties'])) if d['maxDuties'] else 'excluded-zero-cap','difficulty':points[i],'weekdayMonToSun':weekday[i]} for i,d in enumerate(s['doctors'])]})
(out/'per_person.json').write_text(json.dumps(stats,indent=2))
with (out/'traces.json.gz').open('wb') as f:
 with gzip.GzipFile(fileobj=f,mode='wb',mtime=0,filename='') as z:
  z.write(json.dumps({'runs':runs,'perPerson':stats},separators=(',',':')).encode())
print('Validated 48 runs; reports and archive ready')
