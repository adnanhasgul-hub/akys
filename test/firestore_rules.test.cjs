const fs = require('node:fs');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, deleteDoc, collection, getDocs, Timestamp, query, where, limit, updateDoc, runTransaction } = require('firebase/firestore');

(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Local emulator required');
  const env = await initializeTestEnvironment({
    projectId: 'demo-akys',
    firestore: { rules: fs.readFileSync('firestore.rules', 'utf8') },
  });
  try {
    for (const db of [
      env.unauthenticatedContext().firestore(),
      env.authenticatedContext('test-non-admin').firestore(),
      env.authenticatedContext('test-string-claim', { admin: 'true' }).firestore(),
    ]) {
      const ref = doc(db, 'rule_checks/probe');
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, { probe: true }));
      await assertFails(deleteDoc(ref));
    }
    for (const uid of ['test-admin-a', 'test-admin-b']) {
      const ref = doc(env.authenticatedContext(uid, { admin: true }).firestore(), 'rule_checks/probe');
      await assertSucceeds(setDoc(ref, { probe: true }));
      await assertSucceeds(getDoc(ref));
      await assertSucceeds(deleteDoc(ref));
    }
    const admin = env.authenticatedContext('sharing-admin', { admin: true }).firestore();
    const anon = env.unauthenticatedContext().firestore();
    const user = env.authenticatedContext('sharing-user').firestore();
    const token = 'a'.repeat(48);
    const ref = doc(admin, 'shared_schedules/' + token);
    const projection = { schemaVersion: 1, monthId: '2026-11', title: '2026 Kasım', year: 2026, month: 11, days: 30, people: [], duties: {}, dailyTasks: {}, revoked: false, createdAt: Timestamp.now(), expiresAt: Timestamp.fromMillis(Date.now()+86400000) };
    for (const db of [anon, user]) {
      for (const path of ['work_schedule/main', 'work_schedule/main/personnel/p1', 'work_schedule/main/settings/difficulty', 'work_schedule/main/months/2026-11', 'work_schedule/main/months/2026-11/constraints/p1', 'work_schedule/main/months/2026-11/duties/1', 'work_schedule/main/months/2026-11/task_assignments/ward', 'work_schedule/main/months/2026-11/task_overrides/a']) {
        await assertFails(getDoc(doc(db,path)));
        await assertFails(setDoc(doc(db,path), {probe:true}));
      }
    }
    for (const path of ['work_schedule/main', 'work_schedule/main/personnel/p1', 'work_schedule/main/settings/difficulty', 'work_schedule/main/months/2026-11', 'work_schedule/main/months/2026-11/constraints/p1', 'work_schedule/main/months/2026-11/duties/1', 'work_schedule/main/months/2026-11/task_assignments/ward', 'work_schedule/main/months/2026-11/task_overrides/a']) {
      await assertSucceeds(setDoc(doc(admin,path), {probe:true}));
      await assertSucceeds(getDoc(doc(admin,path)));
    }
    for (const db of [anon,user]) {
      await assertFails(getDocs(collection(db,'work_schedule/main/personnel')));
      await assertFails(getDocs(collection(db,'work_schedule/main/months')));
    }
    await assertSucceeds(setDoc(ref, projection));
    for (const db of [anon,user]) {
      await assertSucceeds(getDoc(doc(db, 'shared_schedules/' + token)));
      await assertFails(getDocs(collection(db,'shared_schedules')));
      await assertFails(getDocs(query(collection(db,'shared_schedules'),where('monthId','==','2026-11'),limit(1))));
      await assertFails(updateDoc(doc(db,'shared_schedules/'+token),{revoked:true}));
      await assertFails(setDoc(doc(db,'shared_schedules/'+token),projection));
      await assertFails(deleteDoc(doc(db,'shared_schedules/'+token)));
      await assertFails(getDoc(doc(db,'shared_schedules/'+'b'.repeat(48))));
    }
    await assertFails(setDoc(ref, {...projection, constraints: {private:true}}));
    await assertSucceeds(setDoc(ref,{...projection,revoked:true}));
    await assertFails(getDoc(doc(anon,'shared_schedules/'+token)));
    await assertSucceeds(setDoc(ref,{...projection,expiresAt:Timestamp.fromMillis(1)}));
    await assertFails(getDoc(doc(anon,'shared_schedules/'+token)));
    await assertSucceeds(setDoc(doc(admin,'shared_schedules/short'),projection));
    await assertFails(getDoc(doc(anon,'shared_schedules/short')));
    // Real SDK transaction with V1.2 settings GET + complete month CREATE.
    const difficultySettings = {schemaVersion:1,revision:1,weekdayScores:[3,3,3,1,6,9,5],preHolidayDifficultyScore:6,customHolidays:[]};
    await assertSucceeds(setDoc(doc(admin,'work_schedule/main/settings/difficulty'),difficultySettings));
    const fixture=JSON.parse(fs.readFileSync('test/fixtures/november_2026_difficulty_regression.json','utf8'));
    const monthRef=doc(admin,'work_schedule/main/months/2026-12');
    await assertSucceeds(runTransaction(admin,async tx=>{
      const missing=await tx.get(monthRef);
      const settings=await tx.get(doc(admin,'work_schedule/main/settings/difficulty'));
      if(missing.exists())throw Error('Unexpected existing test month');
      tx.set(monthRef,{...fixture,schemaVersion:3,engineVersion:'1.2.0',month:12,duties:{},difficultySettingsSnapshot:settings.data(),holidayDifficultyOverrides:{},holidayCalendarSnapshot:[{date:'2027-01-01',name:'Yılbaşı',isHalfDay:false,source:'TBB verified calendar',calendarYear:2027,custom:false,triggersPreHoliday:true}]});
    }));
    await assertSucceeds(getDoc(monthRef));
    for(const db of [anon,user]) {
      await assertFails(runTransaction(db,async tx=>{const target=doc(db,'work_schedule/main/months/2027-01');await tx.get(target);await tx.get(doc(db,'work_schedule/main/settings/difficulty'));tx.set(target,{...fixture,year:2027,month:1});}));
    }
    console.log('V1.2 settings admin-only and complete settings-read/month-create transaction passed.');
    console.log('Firestore rules: private admin-only, public token GET only, revocation, expiry and projection allowlist passed.');
  } finally { await env.cleanup(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
