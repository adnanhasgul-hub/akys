const realPost = self.postMessage.bind(self);
self.postMessage = data => {
  const m=JSON.parse(data);
  if(m.type==='event') realPost(JSON.stringify({...m,runId:m.runId-1,nodes:999999999,state:'infeasible',best:null}));
  realPost(data);
  if(m.type==='event') realPost(data); // duplicate same sequence
};
importScripts('../akys_v2_worker.js');
