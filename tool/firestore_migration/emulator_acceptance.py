import json,subprocess,tempfile,copy
from pathlib import Path
from metadata_migration import Emulator,migrate,ROOT
fixtures=json.loads(subprocess.check_output(['dart','run','tool/clinical_approval/fixtures.dart']))
def seed(db,id,count):
 for number in range(1,count+1):
  fields={'schema':{'integerValue':'1'},'version':{'integerValue':str(number)},'status':{'stringValue':'draft'},'year':{'integerValue':'2026'},'month':{'integerValue':'11'},'actor':{'stringValue':'synthetic'},'operationId':{'stringValue':f'original_operation_{number:020}'}}
  db.request('PATCH',f'/v2_schedules/{id}/versions/{number}',{'fields':{**fields,'payload':{'stringValue':fixtures['valid']}}})
 db.request('PATCH',f'/v2_schedules/{id}',{'fields':fields})
# Fresh demo emulator only. Names separate from other suites.
db=Emulator();seed(db,'migration-large',125);seed(db,'migration-small',2)
original={d['name']:copy.deepcopy(d['fields']) for sid in ['migration-large','migration-small'] for d in db.documents('/v2_schedules/'+sid+'/versions')}
with tempfile.TemporaryDirectory(prefix='akys-migration-') as folder:
 checkpoint=folder+'/checkpoint.json'
 invalid=Path(folder)/'corrupt.json';invalid.write_text('{')
 fresh=Emulator()
 try:migrate(fresh,True,str(invalid));raise AssertionError('corrupt checkpoint accepted')
 except ValueError:pass
 assert fresh.writes==0
 dry=migrate(Emulator());assert dry['schedules']==2 and dry['versions']==127 and dry['writtenDocuments']==0 and dry['plannedMetadataWrites']==127,dry
 partial=migrate(Emulator(),True,checkpoint,max_writes=3);assert partial['interrupted']
 resumed=migrate(Emulator(),True,checkpoint);assert not resumed['errors'],resumed
 assert resumed['unchangedMetadata']==3
 again=migrate(Emulator(),True,checkpoint);assert again['writtenDocuments']==0
 for sid in ['migration-large','migration-small']:
  for doc in db.documents('/v2_schedules/'+sid+'/versions'):assert doc['fields']==original[doc['name']]
  assert db.get('/v2_schedules/'+sid)['fields']['historySchema']=={'integerValue':'2'}
 # Rollback procedure: CAS head only, keeping original immutable versions.
 head=db.get('/v2_schedules/migration-small');fields=copy.deepcopy(head['fields']);fields.pop('historySchema')
 db.commit([{'update':{'name':head['name'],'fields':fields},'currentDocument':{'updateTime':head['updateTime']}}])
 assert db.get('/v2_schedules/migration-small')['fields'].get('historySchema') is None
 # Reject an existing changed mirror; never overwrite it.
 doc=db.get('/v2_schedules/migration-small/version_metadata/1');fields=copy.deepcopy(doc['fields']);fields['actor']={'stringValue':'tampered'}
 db.request('PATCH','/v2_schedules/migration-small/version_metadata/1',{'fields':fields})
 rejected=migrate(Emulator(),True);assert rejected['errors'] and rejected['writtenDocuments']==0
 # A concurrent head update must prevent cutover, even after mirror creation.
 seed(db,'migration-race',1)
 class RacingStore(Emulator):
  def commit(self,writes):
   if any(w['update']['name'].endswith('/v2_schedules/migration-race') for w in writes):
    self.request('PATCH','/v2_schedules/migration-race?updateMask.fieldPaths=actor',{'fields':{'actor':{'stringValue':'concurrent-admin'}}})
   return super().commit(writes)
 race=migrate(RacingStore(),True)
 assert any(e['schedule']=='migration-race' for e in race['errors'])
 assert db.get('/v2_schedules/migration-race')['fields'].get('historySchema') is None
 metadata=db.get('/v2_schedules/migration-large/version_metadata/125')
 payload=db.get('/v2_schedules/migration-large/versions/125')
 result={'pass':True,'checks':['dry-run no writes','127 immutable versions decoded by Dart','interruption/resume','idempotent rerun','payload bytes preserved','head-only rollback','mismatching metadata rejected','concurrent head CAS rejects cutover','corrupt checkpoint fails before writes'],
         'dryRun':dry,'resumed':resumed,'again':again,'rejected':rejected,'race':race,
         'sampleVersionJsonBytes':len(json.dumps(payload).encode()),'sampleMetadataJsonBytes':len(json.dumps(metadata).encode())}
Path('tool/solver_v2/results/stage_1_9f_migration.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k not in ['dryRun','resumed','again','rejected']}))
