"""Local configuration contract, NOT Google Cloud IAM integration testing."""
import json
from pathlib import Path
role=json.loads(Path('deployment/approval/runtime-role.json').read_text())
assert set(role['includedPermissions'])=={'datastore.databases.get','datastore.entities.get','datastore.entities.create','datastore.entities.update'}
assert not any('delete' in p or p.startswith(('iam.','firebaseauth.')) for p in role['includedPermissions'])
config=Path('deployment/approval/cloud-run.template.yaml').read_text()
assert 'ingress: internal' in config and "value: 'false'" in config
assert 'REPLACE_WITH_REVIEWED_IMAGE_DIGEST' in config
rules=Path('firestore.rules').read_text()
assert "d.status in ['draft','archived']" in rules
assert "collection != 'v2_schedules'" in rules
result={'pass':True,'checks':5,'scope':'local proposal/static guards only; no IAM binding or cloud resource tested'}
Path('tool/solver_v2/results/stage_1_9f_policy.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
