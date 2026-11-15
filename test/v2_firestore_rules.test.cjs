const fs=require('node:fs');
const assert=require('node:assert/strict');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,getDoc,getDocs,collection,writeBatch,serverTimestamp,updateDoc,deleteDoc,runTransaction}=require('firebase/firestore');
(async()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Emulator required');
 const env=await initializeTestEnvironment({projectId:'demo-akys',firestore:{rules:fs.readFileSync('firestore.rules','utf8')}});
 let checks=0;
 const ok=async p=>{await assertSucceeds(p);checks++},no=async p=>{await assertFails(p);checks++};
 const admin=env.authenticatedContext('admin',{admin:true}).firestore();
 function data(version=1,status='draft',extra={}) {return {schema:1,version,status,year:2026,month:11,actor:'admin',at:serverTimestamp(),operationId:'operation_'+String(version).padStart(20,'0'),summary:'test',sourceId:null,sourceVersion:null,createdBy:'admin',createdAt:serverTimestamp(),...extra};}
 function save(db,id,h,omit){const b=writeBatch(db);b.set(doc(db,'v2_schedules',id),h);if(omit!=='version')b.set(doc(db,'v2_schedules',id,'versions',String(h.version)),{...h,payload:'{}'});if(omit!=='event')b.set(doc(db,'v2_schedules',id,'events',h.operationId),{action:h.status==='archived'?'archived':h.version>1?'draftUpdated':h.sourceId?'revisionCreated':'draftCreated',actor:h.actor,at:serverTimestamp(),version:h.version,operationId:h.operationId});return b.commit();}
 try{
  for(const db of [env.unauthenticatedContext().firestore(),env.authenticatedContext('user').firestore(),env.authenticatedContext('fake',{admin:'true'}).firestore(),env.authenticatedContext('fake2',{admin:1}).firestore()]){
   await no(getDoc(doc(db,'v2_schedules/a')));await no(getDocs(collection(db,'v2_schedules')));await no(save(db,'blocked',data()));
  }
  await no(save(admin,'noevent',data(),'event'));assert.equal((await getDoc(doc(admin,'v2_schedules/noevent'))).exists(),false);checks++;await no(save(admin,'noversion',data(),'version'));
  for(const path of ['v2_schedules/a/versions/1','v2_schedules/a/events/operation_00000000000000000001']){
   await no(getDoc(doc(env.unauthenticatedContext().firestore(),path)));
  }
  await no(save(admin,'data-admin',data(1,'draft',{admin:true})));
  await ok(save(admin,'b-preview',data()));
  await no(updateDoc(doc(admin,'v2_schedules/b-preview'),{status:'approved',transitionProven:true}));
  await ok(save(admin,'a',data()));await ok(getDocs(collection(admin,'v2_schedules')));
  const h=(await getDoc(doc(admin,'v2_schedules/a'))).data();
  await no(updateDoc(doc(admin,'v2_schedules/a'),{status:'approved'}));
  await no(save(admin,'fake-approve',data(1,'approved')));
  await no(save(admin,'fake-proof',data(1,'draft',{approved:true,proved:true})));
  await no(save(admin,'actor',data(1,'draft',{actor:'someone-else'})));
  await no(save(admin,'clock',data(1,'draft',{at:new Date(0)})));
  await no(updateDoc(doc(admin,'v2_schedules/a/versions/1'),{payload:'tampered'}));
  await no(deleteDoc(doc(admin,'v2_schedules/a/versions/1')));
  await no(updateDoc(doc(admin,'v2_schedules/a/events/'+h.operationId),{actor:'evil'}));
  await no(deleteDoc(doc(admin,'v2_schedules/a/events/'+h.operationId)));
  await no(deleteDoc(doc(admin,'v2_schedules/a')));
  await ok(save(admin,'a',data(2,'draft',{createdAt:h.createdAt})));
  await no(save(admin,'a',data(2,'draft',{createdAt:h.createdAt})));
  await no(save(admin,'a',data(3,'draft',{createdAt:h.createdAt,month:12})));
  await ok(save(admin,'revision',data(1,'draft',{sourceId:'a',sourceVersion:1})));
  await no(save(admin,'badsource',data(1,'draft',{sourceId:'missing',sourceVersion:1})));
  const batch=writeBatch(admin);
  for(const [i,action] of ['approvalAttempt','approvalRejected'].entries())batch.set(doc(admin,'v2_schedules/a/events/approval_'+String(i).padStart(20,'0')),{action,actor:'admin',at:serverTimestamp(),version:2,operationId:'approval_'+String(i).padStart(20,'0')});
  await ok(batch.commit());
  const malicious=writeBatch(admin);malicious.set(doc(admin,'v2_schedules/a/events/approval_00000000000000000002'),{action:'approvalSucceeded',actor:'admin',at:serverTimestamp(),version:2,operationId:'approval_00000000000000000002'});await no(malicious.commit());
  await ok(save(admin,'a',data(3,'archived',{createdAt:h.createdAt})));
  await no(save(admin,'a',data(4,'draft',{createdAt:h.createdAt})));
  // Truly concurrent optimistic transactions: only one version wins.
  await ok(save(admin,'race',data()));
  const change=op=>runTransaction(admin,async tx=>{const ref=doc(admin,'v2_schedules/race');const cur=(await tx.get(ref)).data();if(cur.version!==1)throw Error('CONFLICT');const next=data(2,'draft',{createdAt:cur.createdAt,operationId:op});tx.set(ref,next);tx.set(doc(admin,'v2_schedules/race/versions/2'),{...next,payload:'{}'});tx.set(doc(admin,'v2_schedules/race/events/'+op),{action:'draftUpdated',actor:'admin',at:serverTimestamp(),version:2,operationId:op});});
  const race=await Promise.allSettled([change('concurrent_operation_001'),change('concurrent_operation_002')]);assert.equal(race.filter(x=>x.status==='fulfilled').length,1);checks++;
  assert.equal((await getDocs(collection(admin,'v2_schedules/race/versions'))).size,2);checks++;
  // An admin cannot overwrite a seeded, server-owned approved head either.
  await env.withSecurityRulesDisabled(async c=>{const b=writeBatch(c.firestore());b.set(doc(c.firestore(),'v2_schedules/approved'),{...h,status:'approved'});await b.commit();});
  await no(save(admin,'approved',data(2,'draft',{createdAt:h.createdAt})));
  console.log(JSON.stringify({v2RulesChecks:checks,pass:true}));
 } finally{await env.cleanup();}
})().catch(e=>{console.error(e);process.exitCode=1});
