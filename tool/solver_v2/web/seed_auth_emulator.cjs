// Local demo project only. Never accepts a production project or host.
(async()=>{
 const base='http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
 for(const [email,admin] of [['v2-admin@example.test',true],['v2-user@example.test',false]]){
  const created=await fetch(base+'/accounts:signUp?key=demo-api-key',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email,password:'EmulatorOnly123!',returnSecureToken:true})}).then(r=>r.json());
  if(!created.localId)throw Error(JSON.stringify(created));
  const result=await fetch(base+'/accounts:update?key=demo-api-key',{method:'POST',headers:{'content-type':'application/json','authorization':'Bearer owner'},body:JSON.stringify({localId:created.localId,customAttributes:JSON.stringify({admin})})}).then(r=>r.json());
  if(result.error)throw Error(JSON.stringify(result));
 }
 console.log('Local emulator accounts seeded.');
})().catch(e=>{console.error(e);process.exitCode=1;});
