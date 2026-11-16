// Add-only index changes. Never delete indexes or update field exemptions.
const fs=require('node:fs');
const {GoogleAuth}=require('google-auth-library');
async function main(){
 const plan=JSON.parse(fs.readFileSync('deployment/oidc/index-plan.json','utf8'));
 if(plan.project!=='akys-d708a'||!Array.isArray(plan.indexes)||!plan.indexes.length)throw Error('No reviewed index additions');
 for(const item of plan.indexes){
  if(!/^[A-Za-z0-9_-]+$/.test(item.collectionGroup)||!['COLLECTION','COLLECTION_GROUP'].includes(item.queryScope)||!Array.isArray(item.fields)||item.fields.length<2)throw Error('Invalid index plan');
  for(const f of item.fields)if(typeof f.fieldPath!=='string'||!f.fieldPath||Object.keys(f).some(k=>!['fieldPath','order','arrayConfig'].includes(k))||!((['ASCENDING','DESCENDING'].includes(f.order)&&f.arrayConfig===undefined)||(f.arrayConfig==='CONTAINS'&&f.order===undefined)))throw Error('Invalid field');
 }
 const c=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']}).getClient();
 for(const item of plan.indexes){
  try{const r=await c.request({method:'POST',url:`https://firestore.googleapis.com/v1/projects/akys-d708a/databases/(default)/collectionGroups/${item.collectionGroup}/indexes`,data:{queryScope:item.queryScope,fields:item.fields},timeout:30000});console.log(JSON.stringify({operation:r.data.name,status:'requested; readiness must be checked before Hosting'}));}
  catch(e){if(e.response?.status===409)console.log('Index already exists; inspect readiness.');else throw e;}
 }
}
main().catch(e=>{console.error(`Index request rejected/failed; HTTP ${e.response?.status||'not sent'}; details omitted.`);process.exitCode=1;});
