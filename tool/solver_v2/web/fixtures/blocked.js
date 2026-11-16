self.onmessage=e=>{if(JSON.parse(e.data).command==='start'){for(;;){}}};
self.postMessage(JSON.stringify({version:1,type:'ready',runId:0}));
