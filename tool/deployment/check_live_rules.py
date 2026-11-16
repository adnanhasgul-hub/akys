"""Fail closed if active Rules changed since operator review; no network/writes."""
import hashlib,json,os,re
from pathlib import Path
expected=os.environ.get('EXPECTED_RULES','')
if not re.fullmatch('[a-f0-9]{64}',expected):raise SystemExit('Reviewed Rules digest required')
files=json.loads(Path('production-inspection/rules-source.json').read_text())['source']['files']
if len(files)!=1:raise SystemExit('Unexpected multi-file Rules source')
source=files[0]['content'].replace('\r\n','\n').strip()
if hashlib.sha256(source.encode()).hexdigest()!=expected:raise SystemExit('Live Rules changed since review')
releases=list(Path('production-inspection').glob('hosting-*.json'))
if not any(json.loads(p.read_text()).get('releases') for p in releases):raise SystemExit('No prior Hosting release for rollback')
print('Reviewed Rules source and previous Hosting release captured. No data migration/delete is performed.')
