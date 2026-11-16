"""Loopback only. Ephemeral signed test issuer; never trusts unsigned emulator JWTs."""
import base64,json,os,subprocess,tempfile,time,urllib.request,urllib.error,concurrent.futures,socket,argparse
from pathlib import Path
assert os.environ.get('FIRESTORE_EMULATOR_HOST') in ('127.0.0.1:8080','localhost:8080')
root='http://127.0.0.1:8080/v1/projects/demo-akys/databases/(default)/documents'
parser=argparse.ArgumentParser();parser.add_argument('--result',default='tool/solver_v2/results/stage_1_9f_server.json');args=parser.parse_args()
results={'checks':[]}
def http(url,data=None,token='owner',method='POST'):
 req=urllib.request.Request(url,None if data is None else json.dumps(data).encode(),{'Authorization':'Bearer '+token,'Content-Type':'application/json'},method=method)
 try:
  with urllib.request.urlopen(req,timeout=10) as r:return r.status,json.loads(r.read() or '{}')
 except urllib.error.HTTPError as e:return e.code,json.loads(e.read() or '{}')
def encoded(x):
 if isinstance(x,int):return {'integerValue':str(x)}
 return {'stringValue':x}
def seed(name,payload,**extra):
 fields={k:encoded(v) for k,v in dict(schema=1,version=1,status='draft',year=2026,month=11,actor='admin',operationId='original_operation_0001',**extra).items()}
 for suffix,body in [('',fields),('/versions/1',{**fields,'payload':encoded(payload)})]:
  status,_=http(root+'/v2_schedules/'+name+suffix,{'fields':body},method='PATCH');assert status==200
with tempfile.TemporaryDirectory(prefix='akys-approval-') as temp:
 key=Path(temp)/'issuer.pem';subprocess.run(['openssl','genpkey','-algorithm','RSA','-pkeyopt','rsa_keygen_bits:2048','-out',str(key)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 modulus=subprocess.check_output(['openssl','rsa','-in',str(key),'-modulus','-noout']).decode().strip().split('=')[1]
 b64=lambda b:base64.urlsafe_b64encode(b).decode().rstrip('=')
 jwks=Path(temp)/'keys.json';jwks.write_text(json.dumps({'keys':[{'kid':'local-test-key','kty':'RSA','n':b64(bytes.fromhex(modulus)),'e':'AQAB'}]}))
 def token(**claims):
  now=int(time.time());h=b64(json.dumps({'alg':'RS256','kid':'local-test-key'}).encode());data=dict(aud='demo-akys',iss='https://securetoken.google.com/demo-akys',sub='admin',iat=now,auth_time=now,exp=now+300,admin=True);data.update(claims);b=b64(json.dumps(data).encode())
  message=(h+'.'+b).encode();signature=subprocess.check_output(['openssl','dgst','-sha256','-sign',str(key)],input=message)
  return message.decode()+'.'+b64(signature)
 fixtures=json.loads(subprocess.check_output(['dart','run','tool/clinical_approval/fixtures.dart']))
 with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
 service=subprocess.Popen(['dart','run','tool/clinical_approval/server.dart','--emulator-only',str(jwks),str(port)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 try:
  assert service.stdout.readline().startswith('READY')
  endpoint=f'http://127.0.0.1:{port}/approve';good=token()
  def approve(name,auth=good,**extra):return http(endpoint,dict(scheduleId=name,version=1,operationId='test_approval_operation_0001',**extra),auth)
  seed('valid',fixtures['valid'])
  for claims in [dict(admin=False),dict(admin='true'),dict(exp=0),dict(aud='wrong'),dict(iss='wrong'),dict(iat=int(time.time())+10000)]:
   assert approve('valid',token(**claims))[0]==403
  results['checks'].append('signed non-admin, string admin, expired, wrong audience/issuer/future token rejected')
  assert approve('valid','')[0]==403;results['checks'].append('missing token rejected')
  assert approve('valid','fake')[0]==403;results['checks'].append('unsigned/fake token rejected')
  tampered=good.split('.');body=json.loads(base64.urlsafe_b64decode(tampered[1]+'=='));body['sub']='other';tampered[1]=b64(json.dumps(body).encode())
  assert approve('valid','.'.join(tampered))[0]==403;results['checks'].append('tampered signed claims rejected')
  assert approve('valid',proof=True)[0]==409;results['checks'].append('client proof field rejected')
  for kind in ['missing','transition','proof','hard-constraint']:
   seed(kind,fixtures[kind]);assert approve(kind)[0]==409
   status,head=http(root+'/v2_schedules/'+kind,method='GET');assert head['fields']['status']['stringValue']=='draft'
   results['checks'].append(kind+' rejected without writes')
  seed('corrupt','{');assert approve('corrupt')[0]==409;results['checks'].append('corrupt snapshot rejected')
  assert approve('../invalid')[0]==409;results['checks'].append('invalid document path rejected')
  assert approve('unknown')[0]==409;results['checks'].append('unknown schedule rejected')
  assert http(endpoint,dict(scheduleId='valid',version=2,operationId='test_approval_operation_0001'),good)[0]==409
  status,response=approve('valid');assert status==200 and response['idempotent']==False,(status,response)
  status,response=approve('valid');assert status==200 and response['idempotent']==True
  results['checks'].append('A approval and idempotent retry')
  seed('race',fixtures['valid'])
  with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:responses=list(pool.map(lambda _:approve('race'),range(2)))
  assert any(s==200 for s,_ in responses)
  events=http(root+'/v2_schedules/race/server_audit',method='GET')[1]
  assert len(events.get('documents',[]))==1;results['checks'].append('concurrent transaction: single approval audit')
  approved=http(root+'/v2_schedules/valid/versions/1',method='GET')[1]['fields'];assert approved['status']['stringValue']=='approved'
  assert 'optimalityProven' not in approved;results['checks'].append('approved revision has no optimum claim')
  seed('two-admins',fixtures['valid'])
  with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
   responses=list(pool.map(lambda auth:approve('two-admins',auth),[good,token(sub='second-admin')]))
  assert sum(s==200 for s,_ in responses)==1,responses
  events=http(root+'/v2_schedules/two-admins/server_audit',method='GET')[1]
  assert len(events.get('documents',[]))==1
  results['checks'].append('two distinct admins: exactly one immutable approval')
  seed('tampered',fixtures['valid'])
  http(root+'/v2_schedules/tampered/versions/1?updateMask.fieldPaths=month',{'fields':{'month':encoded(12)}},method='PATCH')
  assert approve('tampered')[0]==409
  seed('missing-link',fixtures['valid'])
  http(root+'/v2_schedules/missing-link/versions/1?updateMask.fieldPaths=operationId',{'fields':{}},method='PATCH')
  assert approve('missing-link')[0]==409
  results['checks'].append('modified version metadata and missing snapshot link rejected')
  seed('transaction-fault',fixtures['valid'])
  http(root+'/v2_schedules/transaction-fault/server_audit/test_approval_operation_0001',{'fields':{'action':encoded('existing')}},method='PATCH')
  assert approve('transaction-fault')[0]==409
  for suffix in ['', '/versions/1']:
   assert http(root+'/v2_schedules/transaction-fault'+suffix,method='GET')[1]['fields']['status']['stringValue']=='draft'
  results['checks'].append('commit precondition failure leaves head/version unapproved')
  # A trusted-store corruption must not be accepted as an idempotent retry.
  http(root+'/v2_schedules/valid/versions/1?updateMask.fieldPaths=payload',{'fields':{'payload':encoded(fixtures['transition'])}},method='PATCH')
  assert approve('valid')[0]==409
  results['checks'].append('changed approved snapshot rejected on retry by digest')
  results['pass']=True
 finally:
  service.terminate();service.wait(timeout=10);print(service.stderr.read())
Path(args.result).write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results))
