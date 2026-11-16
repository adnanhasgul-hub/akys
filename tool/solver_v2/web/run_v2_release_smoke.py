"""Smoke the actual lib/main_v2.dart release, without seeded fixtures."""
import functools, http.server, threading, json, re, hashlib
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
result={'errors':[], 'workers':[], 'externalRequests':[]}
with http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(http.server.SimpleHTTPRequestHandler,directory='build/web')) as server:
 threading.Thread(target=server.serve_forever,daemon=True).start()
 with sync_playwright() as p:
  browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
  page=browser.new_page(viewport={'width':414,'height':896})
  result['chromium']=browser.version
  base=f'http://127.0.0.1:{server.server_port}/'
  page.on('pageerror',lambda e:result['errors'].append(str(e)))
  page.on('worker',lambda w:result['workers'].append(w.url))
  page.on('request',lambda r: result['externalRequests'].append(r.url) if not r.url.startswith((base,'data:','blob:')) else None)
  try:
   page.goto(base)
   page.locator('flt-semantics-placeholder').wait_for(state='attached')
   page.evaluate("document.querySelector('flt-semantics-placeholder').click()")
   page.get_by_role('tab',name='Hekimler').click()
   page.get_by_role('button',name='Hekim ekle').click()
   page.get_by_role('textbox',name='Ad soyad',exact=True).fill('Yerel Test Hekimi')
   page.get_by_role('button',name='Uygula',exact=True).click()
   page.get_by_role('button',name='Yeni taslak',exact=True).click()
   page.get_by_role('button',name='Nöbet oluştur',exact=True).click()
   expect(page.get_by_role('group',name=re.compile('^İmkânsızlık kanıtlandı'))).to_be_visible(timeout=20000)
   assert result['workers'] and not result['errors'] and not result['externalRequests'],result
   result['pass']=True
   result['scenario']='actual empty release -> doctor added -> monthly required capacity infeasible -> real Worker proof shown'
   result['appSha256']=hashlib.sha256(Path('build/web/main.dart.js').read_bytes()).hexdigest()
   result['workerSha256']=hashlib.sha256(Path('build/web/akys_v2_worker.js').read_bytes()).hexdigest()
  except Exception as e:
   result['pass']=False;result['failure']=str(e)
   raise
  finally:
   Path('tool/solver_v2/results/stage_1_9b_release_smoke.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
   browser.close()
 server.shutdown()
print(json.dumps(result,indent=2,ensure_ascii=False))
