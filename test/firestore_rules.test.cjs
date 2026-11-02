const fs = require('node:fs');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, deleteDoc } = require('firebase/firestore');

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
    console.log('Firestore rules: anonymous/non-admin denied; two admins allowed.');
  } finally { await env.cleanup(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
