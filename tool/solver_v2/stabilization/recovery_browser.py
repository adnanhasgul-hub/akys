"""Real Chromium WebCrypto + IndexedDB; no Firebase and no production access."""
import functools,http.server,threading,json,argparse
from pathlib import Path
from playwright.sync_api import sync_playwright
parser=argparse.ArgumentParser();parser.add_argument('--result',default='tool/solver_v2/results/stage_1_9e_recovery_browser.json');args=parser.parse_args()
results={'checks':[]}
with http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(http.server.SimpleHTTPRequestHandler,directory='web')) as server:
 threading.Thread(target=server.serve_forever,daemon=True).start()
 with sync_playwright() as p:
  browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
  page=browser.new_page();url=f'http://127.0.0.1:{server.server_port}/'
  # Avoid booting the real Firebase app; only the encryption adapter is loaded.
  page.route('**/flutter_bootstrap.js',lambda r:r.fulfill(body=''))
  page.goto(url);page.wait_for_function('!!window.akysRecovery')
  page.evaluate("async()=>{await akysRecovery.write('a','synthetic confidential draft'); if(await akysRecovery.read('b')!==null)throw Error('owner leak');}")
  results['checks'].append('owner isolation')
  page.reload();page.wait_for_function('!!window.akysRecovery')
  assert page.evaluate("()=>akysRecovery.read('a')")=='synthetic confidential draft'
  results['checks'].append('reload recovery')
  details=page.evaluate("""async()=>{const db=await new Promise(r=>{const q=indexedDB.open('akys-encrypted-recovery-v1');q.onsuccess=()=>r(q.result)});return await new Promise(r=>{const q=db.transaction('entries').objectStore('entries').getAll();q.onsuccess=()=>r(q.result.map(e=>({extractable:e.key.extractable,algorithm:e.key.algorithm.name,fields:Object.keys(e),ciphertext:Array.from(new Uint8Array(e.ciphertext))})))})}""")
  assert details[0]['extractable']==False and details[0]['algorithm']=='AES-GCM'
  assert sorted(details[0]['fields'])==['ciphertext','iv','key']
  assert b'synthetic confidential draft' not in bytes(details[0]['ciphertext'])
  results['checks'].append('nonextractable AES-GCM key; no plaintext persisted')
  page.evaluate("""async()=>{const db=await new Promise(r=>{const q=indexedDB.open('akys-encrypted-recovery-v1');q.onsuccess=()=>r(q.result)});await new Promise(r=>{const t=db.transaction('entries','readwrite'),s=t.objectStore('entries'),q=s.openCursor();q.onsuccess=()=>{const c=q.result;if(c){let v=c.value;new Uint8Array(v.ciphertext)[0]^=1;c.update(v)}};t.oncomplete=r})}""")
  assert page.evaluate("async()=>{try{await akysRecovery.read('a');return false}catch(e){return true}}")
  results['checks'].append('ciphertext tampering rejected')
  page.evaluate("()=>akysRecovery.remove('a')")
  assert page.evaluate("()=>akysRecovery.read('a')") is None
  results['checks'].append('delete clears recovery')
  results.update({'pass':True,'chromium':browser.version});browser.close()
 server.shutdown()
Path(args.result).write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results))
