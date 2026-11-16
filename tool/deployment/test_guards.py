import unittest,copy,json
from pathlib import Path
from guard import validate_inputs,validate_inspection

class DeploymentGuards(unittest.TestCase):
    def setUp(self):
        self.sha='a'*40
        self.env={'EXPECTED_SHA':self.sha,'GITHUB_SHA':self.sha,'CONFIRMATION':'akys-d708a','INSPECTION_RUN':'123','BACKUP_REFERENCE':'reviewed-backup-evidence'}
        self.run={'conclusion':'success','head_sha':self.sha,'path':'.github/workflows/production-inspect.yml','event':'workflow_dispatch','head_branch':'main','repository':'adnanhasgul-hub/akys'}
    def test_valid(self):validate_inputs(self.env);validate_inspection(self.run,self.sha)
    def test_each_required_input(self):
        for key in ['EXPECTED_SHA','CONFIRMATION','INSPECTION_RUN','BACKUP_REFERENCE']:
            with self.subTest(key=key):
                e=copy.copy(self.env);e[key]=''
                with self.assertRaises(ValueError):validate_inputs(e)
    def test_wrong_revision(self):
        e=copy.copy(self.env);e['EXPECTED_SHA']='b'*40
        with self.assertRaises(ValueError):validate_inputs(e)
    def test_run_injection(self):
        for value in ['../123','123;echo bad','$(id)','123\n']:
            e=copy.copy(self.env);e['INSPECTION_RUN']=value
            with self.assertRaises(ValueError):validate_inputs(e)
    def test_run_identity(self):
        for key in self.run:
            with self.subTest(key=key):
                r=copy.copy(self.run);r[key]='wrong'
                with self.assertRaises(ValueError):validate_inspection(r,self.sha)
    def test_no_legacy_credentials_or_automatic_deploy(self):
        for p in Path('.github/workflows').glob('*.yml'):
            text=p.read_text()
            self.assertNotIn('credentials_json',text);self.assertNotIn('FIREBASE_TOKEN',text)
            self.assertNotIn('  push:',text);self.assertNotIn('pull_request',text)
        self.assertFalse(Path('.github/workflows/deploy-hosting.yml').exists())
        self.assertFalse(Path('.github/workflows/deploy-firestore-rules.yml').exists())
    def test_iam_has_no_entity_auth_delete_or_admin(self):
        roles=json.loads(Path('deployment/oidc/iam-proposals.json').read_text())['roles']
        for perms in roles.values():
            for p in perms:
                self.assertFalse(p.startswith(('datastore.entities.','firebaseauth.','iam.')))
                self.assertNotIn('delete',p.lower())
        self.assertNotIn('datastore.indexes.create',roles['readonly'])
    def test_index_plan_empty_requires_review(self):
        self.assertEqual(json.loads(Path('deployment/oidc/index-plan.json').read_text()),{'project':'akys-d708a','indexes':[]})

if __name__=='__main__':unittest.main()
