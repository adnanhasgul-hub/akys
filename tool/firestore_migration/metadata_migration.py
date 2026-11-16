"""Emulator-only resumable metadata backfill. Production procedure is separate.
All original version documents and payload bytes are immutable. No deletes.
"""
import argparse,copy,hashlib,itertools,json,os,subprocess,urllib.request,urllib.error,urllib.parse
from pathlib import Path
ROOT='http://127.0.0.1:8080/v1/projects/demo-akys/databases/(default)/documents'
def write_report(path,data):
 target=Path(path);temporary=target.with_name(target.name+'.tmp')
 with open(temporary,'w',encoding='utf-8') as file:
  json.dump(data,file,indent=2);file.write('\n');file.flush();os.fsync(file.fileno())
 os.replace(temporary,target)
class Conflict(Exception): pass
class Emulator:
 def __init__(self):
  if os.environ.get('FIRESTORE_EMULATOR_HOST') not in ('127.0.0.1:8080','localhost:8080'):raise RuntimeError('Loopback demo emulator required')
  self.reads=0;self.writes=0;self.bytes=0;self.pointAttempts=0;self.missingReads=0;self.queryPages=0;self.emptyQueries=0
 def request(self,method,path,data=None):
  req=urllib.request.Request(ROOT+path,None if data is None else json.dumps(data).encode(),{'Authorization':'Bearer owner','Content-Type':'application/json'},method=method)
  try:
   with urllib.request.urlopen(req,timeout=10) as r:
    raw=r.read();self.bytes+=len(raw);return json.loads(raw or '{}')
  except urllib.error.HTTPError as e:
   raw=e.read();self.bytes+=len(raw)
   try:status=json.loads(raw).get('error',{}).get('status')
   except (ValueError,AttributeError):status=None
   if e.code in (409,412) or status in ('ABORTED','FAILED_PRECONDITION','ALREADY_EXISTS'):raise Conflict('Concurrent change; retry from current immutable versions')
   raise
 def documents(self,path):
  parent,collection=path.rsplit('/',1)
  cursor=None
  while True:
   query={'from':[{'collectionId':collection}],'orderBy':[{'field':{'fieldPath':'__name__'},'direction':'ASCENDING'}],'limit':50}
   if cursor:query['startAt']={'values':[{'referenceValue':cursor}],'before':False}
   self.queryPages+=1
   rows=self.request('POST',parent+':runQuery',{'structuredQuery':query})
   documents=[row['document'] for row in rows if 'document' in row]
   if not documents:self.emptyQueries+=1
   for doc in documents:self.reads+=1;yield doc
   if len(documents)<50:break
   cursor=documents[-1]['name']
 def get(self,path):
  self.pointAttempts+=1
  try:result=self.request('GET',path);self.reads+=1;return result
  except urllib.error.HTTPError as e:
   if e.code==404:self.missingReads+=1;return None
   raise
 def commit(self,writes):
  self.request('POST',':commit',{'writes':writes});self.writes+=len(writes)

def plain(field):
 for kind in ('stringValue','integerValue','nullValue'):
  if kind in field:return int(field[kind]) if kind=='integerValue' else field[kind]
 raise ValueError('Unsupported field')
def validate_version(head,doc):
 f=doc['fields'];h=head['fields'];payload=f.get('payload',{}).get('stringValue')
 if not isinstance(payload,str):raise ValueError('Missing payload')
 data=json.loads(payload)
 if set(data)!={'schema','problem','names','assignments','locks','slotIds','quality'} or data['schema']!=1:raise ValueError('Invalid/portable-proof payload')
 if len(data['assignments'])!=len(data['slotIds']):raise ValueError('Slot cardinality mismatch')
 if f.get('year')!=h.get('year') or f.get('month')!=h.get('month'):raise ValueError('Calendar metadata mismatch')
 if doc['name'].rsplit('/',1)[1]!=str(plain(f['version'])):raise ValueError('Version id mismatch')
 # Not clinical approval: invalid/incomplete drafts remain invalid/incomplete.
 metadata=copy.deepcopy(f);metadata.pop('payload');metadata['historySchema']={'integerValue':'2'}
 return metadata,hashlib.sha256(payload.encode()).hexdigest()

def validated_versions(db,head,sid):
 source=iter(db.documents('/v2_schedules/'+sid+'/versions'))
 while True:
  batch=list(itertools.islice(source,25))
  if not batch:return
  prepared=[(v,*validate_version(head,v)) for v in batch]
  verified=json.loads(subprocess.check_output(['dart','run','tool/firestore_migration/validate_payloads.dart'],input=json.dumps([v['fields']['payload']['stringValue'] for v,_,_ in prepared]).encode(),timeout=60))
  if len(verified)!=len(prepared) or not all(verified):raise ValueError('Independent Dart snapshot decoder rejected data')
  yield from prepared

def migrate(db,apply=False,checkpoint=None,max_writes=None):
 prior=json.loads(Path(checkpoint).read_text()).get('payloadHashes',{}) if checkpoint and Path(checkpoint).exists() else {}
 report={'mode':'apply' if apply else 'dry-run','schedules':0,'versions':0,'plannedMetadataWrites':0,'headSwitches':0,'unchangedMetadata':0,'errors':[],'payloadHashes':{}}
 for head in db.documents('/v2_schedules'):
  sid=head['name'].rsplit('/',1)[1]
  if head['fields'].get('historySchema')=={'integerValue':'2'}:continue
  try:
   count=plain(head['fields']['version']);numbers=set()
   report['schedules']+=1
   for version,metadata,digest in validated_versions(db,head,sid):
    report['versions']+=1
    number=plain(version['fields']['version']);numbers.add(number);path=f'/v2_schedules/{sid}/version_metadata/{number}'
    existing=db.get(path)
    if f'{sid}/{number}' in prior and prior[f'{sid}/{number}']!=digest:raise ValueError('Source payload changed since checkpoint')
    report['payloadHashes'][f'{sid}/{number}']=digest
    if existing:
     if existing['fields']!=metadata:raise ValueError('Existing metadata differs; never overwrite')
     report['unchangedMetadata']+=1
    else:
     report['plannedMetadataWrites']+=1
     if apply:
      db.commit([{'update':{'name':ROOT.split('/v1/')[1]+path,'fields':metadata},'currentDocument':{'exists':False}}])
      if checkpoint:write_report(checkpoint,report)
      if max_writes is not None and db.writes>=max_writes:
       report['interrupted']=True;return report
   if numbers!=set(range(1,count+1)):raise ValueError('History incomplete/noncontiguous')
   # Compare-and-set protects against saves during backfill. Do not modify versions.
   report['headSwitches']+=1
   if apply:
    fields=copy.deepcopy(head['fields']);fields['historySchema']={'integerValue':'2'}
    db.commit([{'update':{'name':head['name'],'fields':fields},'currentDocument':{'updateTime':head['updateTime']}}])
   if checkpoint:write_report(checkpoint,report)
  except (ValueError,KeyError,TypeError,Conflict,urllib.error.URLError,TimeoutError) as error:
   report['errors'].append({'schedule':sid,'reason':str(error)})
 report.update(readDocuments=db.reads,writtenDocuments=db.writes,restResponseBytes=db.bytes,pointReadAttempts=db.pointAttempts,missingDocumentReads=db.missingReads,queryPages=db.queryPages,estimatedDocumentReadsExcludingIndexCharges=db.reads+db.missingReads+db.emptyQueries)
 return report

def main():
 p=argparse.ArgumentParser();p.add_argument('--apply-emulator-only',action='store_true');p.add_argument('--report',required=True);p.add_argument('--checkpoint');a=p.parse_args()
 try:report=migrate(Emulator(),a.apply_emulator_only,a.checkpoint)
 except (urllib.error.URLError,TimeoutError,ValueError) as error:report={'mode':'apply' if a.apply_emulator_only else 'dry-run','errors':[{'fatal':type(error).__name__}],'checkpoint':a.checkpoint}
 write_report(a.report,report);print(json.dumps(report))
 if report['errors']:raise SystemExit(1)
if __name__=='__main__':main()
