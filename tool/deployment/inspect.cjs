// No document or Auth-user reads; output contains configuration, never tokens.
const fs = require('node:fs');
const {GoogleAuth} = require('google-auth-library');
const project='akys-d708a';
async function main(){
 const client=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']}).getClient();
 const get=async url=>(await client.request({url,timeout:30000})).data;
 const dir='production-inspection';fs.mkdirSync(dir,{recursive:true});
 const save=(name,data)=>fs.writeFileSync(`${dir}/${name}.json`,JSON.stringify(data,null,2));
 const list=async(url,key)=>{let all=[],page;do{const u=new URL(url);if(page)u.searchParams.set('pageToken',page);const d=await get(u.href);all.push(...(d[key]||[]));page=d.nextPageToken;}while(page);return all;};
 save('provenance',{project,sha:process.env.GITHUB_SHA,run:process.env.GITHUB_RUN_ID,time:new Date().toISOString(),dataBackupVerified:false,authUsersRead:false});
 const sites=await list(`https://firebasehosting.googleapis.com/v1beta1/projects/${project}/sites`,'sites');save('sites',sites);
 for(const site of sites){const name=site.name.split('/').pop();save(`hosting-${name}`,await get(`https://firebasehosting.googleapis.com/v1beta1/sites/${name}/releases?pageSize=10`));}
 const release=await get(`https://firebaserules.googleapis.com/v1/projects/${project}/releases/cloud.firestore`);save('rules-release',release);
 if(!release.rulesetName?.startsWith(`projects/${project}/rulesets/`))throw Error('Unexpected ruleset');
 save('rules-source',await get(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`));
 save('indexes',await list(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/collectionGroups/-/indexes`,'indexes'));
 save('field-overrides',await list(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/collectionGroups/-/fields?filter=indexConfig.usesAncestorConfig=false`,'fields'));
 save('database',await get(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)`));
 console.log('Read-only configuration captured; no data export or restore verification performed.');
}
main().catch(e=>{console.error(`Inspection failed; HTTP ${e.response?.status||'unavailable'}; credential details omitted.`);process.exitCode=1;});
