"""Fail closed before OIDC exchange; inputs never become shell code."""
import argparse,json,os,re

def validate_inputs(env):
    if env.get('CONFIRMATION') != 'akys-d708a': raise ValueError('Wrong project confirmation')
    sha=env.get('EXPECTED_SHA','')
    if not re.fullmatch('[a-f0-9]{40}',sha) or sha != env.get('GITHUB_SHA'): raise ValueError('Reviewed SHA mismatch')
    if not re.fullmatch('[0-9]+',env.get('INSPECTION_RUN','')): raise ValueError('Invalid inspection run')
    if not env.get('BACKUP_REFERENCE','').strip(): raise ValueError('Backup evidence required')

def validate_inspection(data,sha):
    expected={'conclusion':'success','head_sha':sha,'path':'.github/workflows/production-inspect.yml','event':'workflow_dispatch','head_branch':'main','repository':'adnanhasgul-hub/akys'}
    if any(data.get(k)!=v for k,v in expected.items()): raise ValueError('Inspection identity/revision mismatch')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--inspection');args=parser.parse_args()
    if args.inspection: validate_inspection(json.load(open(args.inspection)),os.environ['GITHUB_SHA'])
    else: validate_inputs(os.environ)
