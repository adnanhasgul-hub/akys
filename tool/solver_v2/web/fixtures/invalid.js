const realPost = self.postMessage.bind(self);
self.postMessage = data => {
  const m=JSON.parse(data);
  if(m.best) m.best.assignments[0]=-1;
  realPost(JSON.stringify(m));
};
importScripts('../akys_v2_worker.js');
