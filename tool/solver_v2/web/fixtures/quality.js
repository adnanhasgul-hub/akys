const realPost = self.postMessage.bind(self);
self.postMessage = data => {
  const m=JSON.parse(data);
  if(m.best) m.best.clinicalQuality.components[0].numerator='999999999999999999999999999';
  realPost(JSON.stringify(m));
};
importScripts('../akys_v2_worker.js');
