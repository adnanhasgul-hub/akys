const realPost = self.postMessage.bind(self); let armed = false;
self.postMessage = data => {
  realPost(data); const m=JSON.parse(data);
  if(m.best && !armed) {armed=true;setTimeout(()=>{throw Error('intentional worker crash');},20);}
};
importScripts('../akys_v2_worker.js');
