// Read-only production verification. Never logs credentials or response bodies.
// Run only in GitHub Actions after the existing Google auth action.
const fs = require('node:fs');
const { createHash, randomBytes } = require('node:crypto');
const { GoogleAuth } = require('google-auth-library');
const project = 'akys-d708a';
class VerificationFailure extends Error {}
const normalize = value => value.replace(/\r\n/g, '\n').trim();

async function verify() {
  if (process.env.GITHUB_ACTIONS !== 'true') {
    throw new VerificationFailure('This verifier runs only in GitHub Actions; no local production credentials are required.');
  }
  const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
  const client = await auth.getClient();
  const release = await client.request({ url: `https://firebaserules.googleapis.com/v1/projects/${project}/releases/cloud.firestore` });
  const rulesetName = release.data.rulesetName;
  if (typeof rulesetName !== 'string' || !rulesetName.startsWith(`projects/${project}/rulesets/`)) {
    throw new VerificationFailure('Production release references an unexpected ruleset.');
  }
  const ruleset = await client.request({ url: `https://firebaserules.googleapis.com/v1/${rulesetName}` });
  const files = ruleset.data.source?.files;
  const expected = normalize(fs.readFileSync('firestore.rules', 'utf8'));
  if (!Array.isArray(files) || files.length !== 1 || normalize(files[0].content || '') !== expected) {
    throw new VerificationFailure('Active production rules do not match the tested repository source.');
  }
  console.log(`Active production rules match repository SHA-256: ${createHash('sha256').update(expected).digest('hex')}`);

  const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
  const absentToken = randomBytes(24).toString('hex');
  const probes = [
    ['anonymous private registry GET', `${base}/work_schedule/main`],
    ['anonymous private personnel LIST', `${base}/work_schedule/main/personnel?pageSize=1`],
    ['anonymous private months LIST', `${base}/work_schedule/main/months?pageSize=1`],
    ['anonymous public projection LIST', `${base}/shared_schedules?pageSize=1`],
    ['anonymous invalid-token GET', `${base}/shared_schedules/invalid-token`],
    ['anonymous nonexistent-token GET', `${base}/shared_schedules/${absentToken}`],
  ];
  for (const [label, url] of probes) {
    // No OAuth header: these requests exercise anonymous client rules, not IAM.
    const response = await fetch(url, { redirect: 'error', signal: AbortSignal.timeout(30000) });
    const body = await response.json();
    if (response.status !== 403 || body.error?.status !== 'PERMISSION_DENIED') {
      throw new VerificationFailure(`${label}: expected PERMISSION_DENIED, received HTTP ${response.status}.`);
    }
    console.log(`PASS: ${label} denied.`);
  }
  console.log('No production documents were created, updated, deleted or enumerated.');
  console.log('Authenticated non-admin/admin, valid/revoked/expired token and public-write behavior are covered by the mandatory emulator suite, not live user credentials.');
}
verify().catch(error => {
  // SDK errors can include request headers; print only a controlled status.
  const status = error.response?.status;
  const safe = error instanceof VerificationFailure ? error.message : `Google API verification failed${status ? ` (HTTP ${status})` : ''}; credential details omitted.`;
  console.error(safe);
  process.exitCode = 1;
});
